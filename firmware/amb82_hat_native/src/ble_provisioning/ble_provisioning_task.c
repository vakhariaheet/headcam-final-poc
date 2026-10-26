// Reserve one SET_STA attempt across the queue and asynchronous pipeline task.
// BLE callbacks only validate and enqueue; Wi-Fi/video run on normal tasks.
// At boot, the worker also rejoins the saved network, retrying until it
// succeeds or an app request supersedes it. An app request takes over from a
// saved attempt immediately; the pipeline aborts that association.

#include <string.h>
#include <stdio.h>

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

#include "ble_provisioning_task.h"
#include "ble_provisioning_service.h"
#include "mmf2_hat_pipeline_init.h"
#include "hat_wifi_store.h"

#define BLE_PROVISIONING_QUEUE_LEN 2
#define BLE_PROVISIONING_SSID_MAX_LEN HAT_WIFI_SSID_MAX_LEN
#define BLE_PROVISIONING_PASS_MAX_LEN HAT_WIFI_PASS_MAX_LEN
#define BLE_PROVISIONING_SESSION_TOKEN_MAX_LEN 400
#define BLE_PROVISIONING_STATUS_MAX_LEN 256
#define BLE_PROVISIONING_SAVED_RETRY_MIN_MS (15 * 1000)
#define BLE_PROVISIONING_SAVED_RETRY_MAX_MS (2 * 60 * 1000)

typedef struct {
	uint8_t conn_id;
	char ssid[BLE_PROVISIONING_SSID_MAX_LEN];
	char pass[BLE_PROVISIONING_PASS_MAX_LEN];
	char session_token[BLE_PROVISIONING_SESSION_TOKEN_MAX_LEN];
} ble_provisioning_request_t;

typedef enum {
	PROVISIONING_OWNER_NONE,
	PROVISIONING_OWNER_SAVED, // boot-time rejoin; any app request preempts it
	PROVISIONING_OWNER_APP,   // one app SET_STA at a time
} ble_provisioning_owner_t;

static QueueHandle_t ble_provisioning_queue;
// Guarded by critical sections, as is the saved-retry schedule below.
static ble_provisioning_owner_t provisioning_owner;

// hat_pipeline_result_cb carries no conn_id of its own — only one app
// attempt is ever in flight at a time (APP_MAX_LINKS == 1), so a single
// static slot is enough to route the result back to the right connection.
static uint8_t ble_provisioning_app_conn_id;

static bool saved_retry_scheduled;
static TickType_t saved_retry_at;
static uint32_t saved_retry_delay_ms = BLE_PROVISIONING_SAVED_RETRY_MIN_MS;

static void ble_provisioning_notify_result(uint8_t conn_id, bool success, const char *ip, const char *reason)
{
	char status[BLE_PROVISIONING_STATUS_MAX_LEN];
	int len;
	if (success) {
		len = snprintf(status, sizeof(status), "{\"status\":\"connected\",\"ip\":\"%s\"}", ip);
	} else {
		len = snprintf(status, sizeof(status), "{\"status\":\"error\",\"reason\":\"%s\"}", reason);
	}
	if (len > 0 && (size_t)len < sizeof(status)) {
		ble_provisioning_service_notify_status(conn_id, status, (uint16_t)len);
	}
}

static void ble_provisioning_on_app_result(bool success, const char *ip, const char *reason)
{
	ble_provisioning_notify_result(ble_provisioning_app_conn_id, success, ip, reason);
	taskENTER_CRITICAL();
	provisioning_owner = PROVISIONING_OWNER_NONE;
	taskEXIT_CRITICAL();
}

// A saved attempt that an app request took over must not touch the
// reservation or the cached status; the app request now owns both.
static void ble_provisioning_on_saved_result(bool success, const char *ip, const char *reason)
{
	taskENTER_CRITICAL();
	bool current = provisioning_owner == PROVISIONING_OWNER_SAVED;
	if (current) {
		provisioning_owner = PROVISIONING_OWNER_NONE;
		saved_retry_scheduled = !success;
		if (!success) {
			saved_retry_at = xTaskGetTickCount() + pdMS_TO_TICKS(saved_retry_delay_ms);
			saved_retry_delay_ms *= 2;
			if (saved_retry_delay_ms > BLE_PROVISIONING_SAVED_RETRY_MAX_MS) {
				saved_retry_delay_ms = BLE_PROVISIONING_SAVED_RETRY_MAX_MS;
			}
		}
	}
	taskEXIT_CRITICAL();
	if (current) ble_provisioning_notify_result(BLE_PROVISIONING_NO_CONN, success, ip, reason);
}

static void ble_provisioning_handle(const ble_provisioning_request_t *req)
{
	bool saved = req->conn_id == BLE_PROVISIONING_NO_CONN;
	if (saved) {
		taskENTER_CRITICAL();
		bool current = provisioning_owner == PROVISIONING_OWNER_SAVED;
		taskEXIT_CRITICAL();
		if (!current) return; // an app request took over before this ran
		if (!hat_pipeline_start(req->ssid, req->pass, ble_provisioning_on_saved_result)) {
			// The camera failed or a request is pending; a saved retry cannot help.
			taskENTER_CRITICAL();
			if (provisioning_owner == PROVISIONING_OWNER_SAVED) provisioning_owner = PROVISIONING_OWNER_NONE;
			saved_retry_scheduled = false;
			taskEXIT_CRITICAL();
		}
		return;
	}

	if (strlen(req->session_token) > 0) {
		printf("\r\n[ble_provisioning] SET_STA with session_token (len=%d) — not yet bound to an "
			   "account server-side, see README\r\n",
			   (int)strlen(req->session_token));
	}
	ble_provisioning_app_conn_id = req->conn_id;
	if (!hat_pipeline_start(req->ssid, req->pass, ble_provisioning_on_app_result)) {
		ble_provisioning_on_app_result(false, NULL, "pipeline_busy_or_restart_required");
	}
}

// Reserves the worker for a saved-network attempt. False if nothing is
// saved, or any request currently owns the worker.
static bool ble_provisioning_enqueue_saved(void)
{
	hat_wifi_credentials_t saved;
	if (!hat_wifi_store_load(&saved)) return false;

	taskENTER_CRITICAL();
	bool available = ble_provisioning_queue && provisioning_owner == PROVISIONING_OWNER_NONE;
	if (available) provisioning_owner = PROVISIONING_OWNER_SAVED;
	taskEXIT_CRITICAL();
	if (!available) return false;

	ble_provisioning_request_t req = {0};
	req.conn_id = BLE_PROVISIONING_NO_CONN;
	memcpy(req.ssid, saved.ssid, sizeof(req.ssid));
	memcpy(req.pass, saved.pass, sizeof(req.pass));
	if (xQueueSend(ble_provisioning_queue, &req, 0) != pdPASS) {
		taskENTER_CRITICAL();
		if (provisioning_owner == PROVISIONING_OWNER_SAVED) provisioning_owner = PROVISIONING_OWNER_NONE;
		taskEXIT_CRITICAL();
		return false;
	}
	printf("\r\n[ble_provisioning] rejoining saved Wi-Fi network\r\n");
	return true;
}

static TickType_t ble_provisioning_wait_ticks(void)
{
	taskENTER_CRITICAL();
	bool scheduled = saved_retry_scheduled;
	TickType_t due = saved_retry_at;
	taskEXIT_CRITICAL();
	if (!scheduled) return portMAX_DELAY;
	TickType_t now = xTaskGetTickCount();
	return (TickType_t)(due - now) > pdMS_TO_TICKS(BLE_PROVISIONING_SAVED_RETRY_MAX_MS) ? 0 : due - now;
}

static void ble_provisioning_task(void *param)
{
	(void)param;
	ble_provisioning_request_t req;

	while (1) {
		if (xQueueReceive(ble_provisioning_queue, &req, ble_provisioning_wait_ticks()) == pdPASS) {
			ble_provisioning_handle(&req);
			continue;
		}
		taskENTER_CRITICAL();
		bool due = saved_retry_scheduled;
		saved_retry_scheduled = false;
		taskEXIT_CRITICAL();
		// A busy worker means an app request is running; it supersedes the retry.
		if (due) ble_provisioning_enqueue_saved();
	}
}

bool ble_provisioning_task_init(void)
{
	if (ble_provisioning_queue) return true;
	ble_provisioning_queue = xQueueCreate(BLE_PROVISIONING_QUEUE_LEN, sizeof(ble_provisioning_request_t));
	if (!ble_provisioning_queue) return false;
	if (xTaskCreate(ble_provisioning_task, (const char *)"ble_provisioning", 2048, NULL, tskIDLE_PRIORITY + 1,
					NULL) != pdPASS) {
		printf("\r\n[ble_provisioning] ble_provisioning_task: Create Task Error\r\n");
		vQueueDelete(ble_provisioning_queue);
		ble_provisioning_queue = NULL;
		return false;
	}
	return true;
}

bool ble_provisioning_request_saved_connect(void)
{
	return ble_provisioning_enqueue_saved();
}

bool ble_provisioning_request_connect(uint8_t conn_id, const char *ssid, const char *pass,
									   const char *session_token)
{
	if (!ssid || !pass || !ssid[0] || strlen(ssid) >= BLE_PROVISIONING_SSID_MAX_LEN ||
		strlen(pass) >= BLE_PROVISIONING_PASS_MAX_LEN ||
		(strlen(pass) > 0 && strlen(pass) < 8) ||
		(session_token && strlen(session_token) >= BLE_PROVISIONING_SESSION_TOKEN_MAX_LEN) ||
		conn_id == BLE_PROVISIONING_NO_CONN) {
		return false;
	}
	// An app request preempts a saved-network attempt and cancels its retries.
	taskENTER_CRITICAL();
	ble_provisioning_owner_t previous = provisioning_owner;
	bool available = ble_provisioning_queue && previous != PROVISIONING_OWNER_APP;
	if (available) {
		provisioning_owner = PROVISIONING_OWNER_APP;
		saved_retry_scheduled = false;
	}
	taskEXIT_CRITICAL();
	if (!available) return false;

	ble_provisioning_request_t req = {0};
	req.conn_id = conn_id;
	strncpy(req.ssid, ssid, sizeof(req.ssid) - 1);
	strncpy(req.pass, pass, sizeof(req.pass) - 1);
	if (session_token) {
		strncpy(req.session_token, session_token, sizeof(req.session_token) - 1);
	}

	if (xQueueSend(ble_provisioning_queue, &req, 0) != pdPASS) {
		// The preempted saved attempt is already abandoned; report nothing for it.
		taskENTER_CRITICAL();
		provisioning_owner = PROVISIONING_OWNER_NONE;
		taskEXIT_CRITICAL();
		return false;
	}
	return true;
}
