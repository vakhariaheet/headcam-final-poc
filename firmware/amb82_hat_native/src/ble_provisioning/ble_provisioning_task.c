// Reserve one SET_STA attempt across the queue and asynchronous pipeline task.
// BLE callbacks only validate and enqueue; Wi-Fi/video run on normal tasks.

#include <string.h>
#include <stdio.h>

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

#include "ble_provisioning_task.h"
#include "ble_provisioning_service.h"
#include "mmf2_hat_pipeline_init.h"

#define BLE_PROVISIONING_QUEUE_LEN 2
#define BLE_PROVISIONING_SSID_MAX_LEN 33
#define BLE_PROVISIONING_PASS_MAX_LEN 65
#define BLE_PROVISIONING_SESSION_TOKEN_MAX_LEN 400
#define BLE_PROVISIONING_STATUS_MAX_LEN 256

typedef struct {
	uint8_t conn_id;
	char ssid[BLE_PROVISIONING_SSID_MAX_LEN];
	char pass[BLE_PROVISIONING_PASS_MAX_LEN];
	char session_token[BLE_PROVISIONING_SESSION_TOKEN_MAX_LEN];
} ble_provisioning_request_t;

static QueueHandle_t ble_provisioning_queue;
static bool provisioning_busy;

// hat_pipeline_result_cb carries no conn_id of its own — only one
// provisioning attempt is ever in flight at a time (APP_MAX_LINKS == 1), so
// a single static slot is enough to route the result back to the right
// connection.
static uint8_t ble_provisioning_pending_conn_id;

static void ble_provisioning_on_wifi_result(bool success, const char *ip, const char *reason)
{
	char status[BLE_PROVISIONING_STATUS_MAX_LEN];
	int len;
	if (success) {
		len = snprintf(status, sizeof(status), "{\"status\":\"connected\",\"ip\":\"%s\"}", ip);
	} else {
		len = snprintf(status, sizeof(status), "{\"status\":\"error\",\"reason\":\"%s\"}", reason);
	}
	if (len > 0 && (size_t)len < sizeof(status)) {
		ble_provisioning_service_notify_status(ble_provisioning_pending_conn_id, status, (uint16_t)len);
	}
	taskENTER_CRITICAL();
	provisioning_busy = false;
	taskEXIT_CRITICAL();
}

static void ble_provisioning_task(void *param)
{
	(void)param;
	ble_provisioning_request_t req;

	while (1) {
		if (xQueueReceive(ble_provisioning_queue, &req, portMAX_DELAY) == pdPASS) {
			if (strlen(req.session_token) > 0) {
				printf("\r\n[ble_provisioning] SET_STA with session_token (len=%d) — not yet bound to an "
					   "account server-side, see README\r\n",
					   (int)strlen(req.session_token));
			}
			ble_provisioning_pending_conn_id = req.conn_id;
			if (!hat_pipeline_start(req.ssid, req.pass, ble_provisioning_on_wifi_result)) {
				ble_provisioning_on_wifi_result(false, NULL, "pipeline_active_restart_required");
			}
		}
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

bool ble_provisioning_request_connect(uint8_t conn_id, const char *ssid, const char *pass,
									   const char *session_token)
{
	if (!ssid || !pass || !ssid[0] || strlen(ssid) >= BLE_PROVISIONING_SSID_MAX_LEN ||
		strlen(pass) >= BLE_PROVISIONING_PASS_MAX_LEN ||
		(strlen(pass) > 0 && strlen(pass) < 8) ||
		(session_token && strlen(session_token) >= BLE_PROVISIONING_SESSION_TOKEN_MAX_LEN)) {
		return false;
	}
	taskENTER_CRITICAL();
	bool available = ble_provisioning_queue && !provisioning_busy;
	if (available) provisioning_busy = true;
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
		taskENTER_CRITICAL();
		provisioning_busy = false;
		taskEXIT_CRITICAL();
		return false;
	}
	return true;
}
