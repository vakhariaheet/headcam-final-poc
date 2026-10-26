// BLE-provisioned Wi-Fi and H.264 capture into an outbound RTMP sink.
// Frames are discarded while idle; no local streaming server is opened.

#include <stdio.h>
#include <string.h>

#include "mmf2_link.h"
#include "mmf2_siso.h"
#include "module_video.h"
#include "module_hat_rtmp.h"
#include "mmf2_pro2_video_config.h"
#include "sensor.h"
#include "log_service.h"

#include "FreeRTOS.h"
#include "task.h"
#include "sys_api.h"
#include "wifi_conf.h"
#include "lwip_netconf.h"

#include "mmf2_hat_pipeline_init.h"
#include "ble_provisioning_service.h"
#include "hat_camera_guard.h"
#include "hat_wifi_store.h"
#include "hat_telemetry.h"

#define HAT_VIDEO_CHANNEL 0
#define HAT_VIDEO_BPS (2 * 1024 * 1024)
#define HAT_VIDEO_RCMODE 2 // 1: CBR, 2: VBR
#define HAT_WIFI_CONNECT_TIMEOUT_MS (30 * 1000)
#define HAT_NO_VIDEO_RESET_TIMEOUT_MS (30 * 1000)
#define HAT_SUPERVISE_INTERVAL_MS (10 * 1000)
// Lets the camera_fault notification leave the radio before a reboot.
#define HAT_FAULT_NOTIFY_DELAY_MS 2000

typedef enum {
	HAT_PIPELINE_IDLE,     // no camera yet; a request may start one
	HAT_PIPELINE_STARTING, // first Wi-Fi association and camera bring-up
	HAT_PIPELINE_RUNNING,  // camera up; requests become network switches
	HAT_PIPELINE_FAILED,   // camera or supervisor stopped; reset required
} hat_pipeline_state_t;

typedef struct {
	hat_wifi_credentials_t credentials;
	hat_pipeline_result_cb result_cb;
} hat_pipeline_request_t;

static hat_pipeline_state_t hat_pipeline_state;
static TaskHandle_t hat_pipeline_task_handle;
// Owned by the pipeline task once it runs; written by start() only while IDLE.
static hat_pipeline_request_t hat_active_request;
// Network-switch handoff, guarded by critical sections.
static hat_pipeline_request_t hat_pending_request;
static bool hat_switch_pending;

static mm_context_t *hat_video_ctx = NULL;
static mm_context_t *hat_sink_ctx = NULL;
static mm_siso_t *hat_siso_video_cloud = NULL;

static video_params_t hat_video_params = {
	.stream_id = HAT_VIDEO_CHANNEL,
	.type = VIDEO_H264,
	.bps = HAT_VIDEO_BPS,
	.rc_mode = HAT_VIDEO_RCMODE,
	.use_static_addr = 1
};

// Returned when a newer request arrived during association; compared by pointer.
static const char hat_superseded[] = "superseded";

static bool hat_request_pending(void)
{
	taskENTER_CRITICAL();
	bool pending = hat_switch_pending;
	taskEXIT_CRITICAL();
	return pending;
}

// Takes the pending request, if any. When none is pending, atomically applies
// idle_state (if not NULL) so start() cannot queue a request nobody will run.
static bool hat_take_pending(hat_pipeline_request_t *out, const hat_pipeline_state_t *idle_state)
{
	taskENTER_CRITICAL();
	bool pending = hat_switch_pending;
	if (pending) {
		*out = hat_pending_request;
		hat_switch_pending = false;
	} else if (idle_state) {
		hat_pipeline_state = *idle_state;
	}
	taskEXIT_CRITICAL();
	return pending;
}

// Association uses the asynchronous SDK API so the 30-second deadline includes
// the handshake itself, and a newer request aborts it within 100 ms. DHCP has
// its own SDK timeout, cannot be interrupted, and must succeed separately.
static const char *hat_wifi_connect(const char *ssid, const char *pass, char *ip_out, size_t ip_out_len)
{
	rtw_network_info_t connect_param = {0};
	connect_param.ssid.len = strlen(ssid);
	memcpy(connect_param.ssid.val, ssid, connect_param.ssid.len);
	connect_param.password = (unsigned char *)pass;
	connect_param.password_len = strlen(pass);
	connect_param.security_type = pass[0] ? RTW_SECURITY_WPA2_AES_PSK : RTW_SECURITY_OPEN;
	connect_param.key_id = -1;

	// Application owns the deadline and explicit retry, not the driver.
	wifi_config_autoreconnect(0, 0, 0);
	TickType_t started = xTaskGetTickCount();
	if (wifi_connect(&connect_param, 0) != RTW_SUCCESS) {
		return "wifi_connect_failed";
	}
	while (wifi_is_connected_to_ap() != RTW_SUCCESS) {
		if (hat_request_pending()) {
			wifi_disconnect();
			return hat_superseded;
		}
		if (wifi_get_join_status() == RTW_JOINSTATUS_FAIL) {
			wifi_disconnect();
			return "wifi_connect_failed";
		}
		if ((TickType_t)(xTaskGetTickCount() - started) >= pdMS_TO_TICKS(HAT_WIFI_CONNECT_TIMEOUT_MS)) {
			wifi_disconnect();
			return "wifi_connect_timeout";
		}
		vTaskDelay(pdMS_TO_TICKS(100));
	}
	if (LwIP_DHCP(0, DHCP_START) != DHCP_ADDRESS_ASSIGNED) {
		wifi_disconnect();
		return "dhcp_failed";
	}
	unsigned char *ip = LwIP_GetIP(0);
	if (!ip || !(ip[0] | ip[1] | ip[2] | ip[3]) || wifi_is_connected_to_ap() != RTW_SUCCESS) {
		wifi_disconnect();
		return "dhcp_failed";
	}
	snprintf(ip_out, ip_out_len, "%u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);
	printf("\r\n[hat] Wi-Fi connected, IP: %s\r\n", ip_out);
	return NULL;
}

static void hat_wifi_remember(const hat_wifi_credentials_t *credentials)
{
	if (!hat_wifi_store_save(credentials->ssid, credentials->pass)) {
		printf("\r\n[hat] saving Wi-Fi credentials failed; re-pair after reboot\r\n");
	}
}

static const char *hat_video_start(void)
{
	hat_video_params.resolution = VIDEO_FHD;
	hat_video_params.width = sensor_params[USE_SENSOR].sensor_width;
	hat_video_params.height = sensor_params[USE_SENSOR].sensor_height;
	hat_video_params.fps = sensor_params[USE_SENSOR].sensor_fps;
	hat_video_params.gop = sensor_params[USE_SENSOR].sensor_fps; // 1s keyframe interval

	int voe_heap_size = video_voe_presetting(1, hat_video_params.width, hat_video_params.height, HAT_VIDEO_BPS, 0,
						  0, 0, 0, 0, 0,
						  0, 0, 0, 0, 0,
						  0, 0, 0);
	printf("\r\n[hat] voe heap size = %d\r\n", voe_heap_size);
	if (voe_heap_size <= 0) return "video_heap_failed";

	hat_video_ctx = mm_module_open(&video_module);
	if (!hat_video_ctx) {
		return "video_open_failed";
	}
	if (mm_module_ctrl(hat_video_ctx, CMD_VIDEO_SET_PARAMS, (int)&hat_video_params) < 0) return "pipeline_config_failed";
	if (mm_module_ctrl(hat_video_ctx, MM_CMD_SET_QUEUE_LEN, hat_video_params.fps * 3) < 0) return "pipeline_config_failed";
	if (mm_module_ctrl(hat_video_ctx, MM_CMD_INIT_QUEUE_ITEMS, MMQI_FLAG_DYNAMIC) < 0) return "pipeline_config_failed";

	hat_sink_ctx = mm_module_open(&hat_rtmp_module);
	if (!hat_sink_ctx) return "cloud_sink_failed";

	hat_siso_video_cloud = siso_create();
	if (!hat_siso_video_cloud) {
		return "video_link_failed";
	}
	siso_ctrl(hat_siso_video_cloud, MMIC_CMD_ADD_INPUT, (uint32_t)hat_video_ctx, 0);
	siso_ctrl(hat_siso_video_cloud, MMIC_CMD_ADD_OUTPUT, (uint32_t)hat_sink_ctx, 0);
	if (siso_start(hat_siso_video_cloud) < 0) return "video_link_failed";

	video_show_fps(1);
	if (mm_module_ctrl(hat_video_ctx, CMD_VIDEO_APPLY, HAT_VIDEO_CHANNEL) < 0) {
		return "video_start_failed";
	}
	TickType_t started = xTaskGetTickCount();
	while (video_get_cb_fps(HAT_VIDEO_CHANNEL) <= 0) {
		if ((TickType_t)(xTaskGetTickCount() - started) >= pdMS_TO_TICKS(5000)) {
			return "video_no_frames";
		}
		vTaskDelay(pdMS_TO_TICKS(100));
	}

	hat_stream_camera_ready();
	hat_telemetry_start(hat_video_ctx, HAT_VIDEO_CHANNEL);
	printf("\r\n[hat] Camera ready; cloud publisher idle (no local RTSP server)\r\n");
	return NULL;
}

static void hat_pipeline_fail(void)
{
	taskENTER_CRITICAL();
	hat_pipeline_state = HAT_PIPELINE_FAILED;
	taskEXIT_CRITICAL();
}

// Fails the active and any queued request, tells the owner's app, then either
// reboots for another attempt or latches FAILED (hat_camera_guard.h). Does
// not return when rebooting.
static void hat_pipeline_camera_fault(const char *reason, bool active_waiting)
{
	hat_pipeline_fail();
	if (active_waiting && hat_active_request.result_cb) hat_active_request.result_cb(false, NULL, reason);
	hat_pipeline_request_t queued;
	if (hat_take_pending(&queued, NULL) && queued.result_cb) queued.result_cb(false, NULL, reason);

	hat_camera_action_t action = hat_camera_guard_fault();
	bool restarting = action == HAT_CAMERA_RESTART;
	char json[160];
	int len = snprintf(json, sizeof(json),
					   "{\"event\":\"camera_fault\",\"reason\":\"%s\",\"action\":\"%s\",\"restarts\":%u,\"max\":%u}",
					   reason, restarting ? "restarting" : "stopped",
					   (unsigned)hat_camera_guard_restarts(), (unsigned)HAT_CAMERA_MAX_RESTARTS);
	if (len > 0 && len < (int)sizeof(json)) ble_provisioning_service_notify_event(json, (uint16_t)len);
	if (!restarting) {
		printf("\r\n[hat] camera fault (%s): giving up after %u restarts; power-cycle the hat\r\n",
			   reason, (unsigned)HAT_CAMERA_MAX_RESTARTS);
		return;
	}
	printf("\r\n[hat] camera fault (%s): restart %u of %u\r\n",
		   reason, (unsigned)hat_camera_guard_restarts(), (unsigned)HAT_CAMERA_MAX_RESTARTS);
	vTaskDelay(pdMS_TO_TICKS(HAT_FAULT_NOTIFY_DELAY_MS));
	sys_reset();
}

// Runs queued network switches on the pipeline task; a newer request
// supersedes one still associating. The RTMP sender reconnects on its own
// once the new association has an address.
static void hat_pipeline_switch(char *ip, size_t ip_len)
{
	hat_pipeline_request_t request;
	while (hat_take_pending(&request, NULL)) {
		const hat_wifi_credentials_t *current = &hat_active_request.credentials;
		bool same_network = strcmp(request.credentials.ssid, current->ssid) == 0 &&
							strcmp(request.credentials.pass, current->pass) == 0;
		const char *reason = NULL;
		if (!same_network || wifi_is_connected_to_ap() != RTW_SUCCESS) {
			printf("\r\n[hat] switching Wi-Fi network\r\n");
			wifi_disconnect();
			reason = hat_wifi_connect(request.credentials.ssid, request.credentials.pass, ip, ip_len);
		}
		if (!reason) {
			hat_active_request.credentials = request.credentials;
			hat_wifi_remember(&request.credentials);
		}
		if (request.result_cb) request.result_cb(reason == NULL, reason ? NULL : ip, reason);
	}
}

static void hat_pipeline_task(void *param)
{
	(void)param;
	hat_wifi_credentials_t *credentials = &hat_active_request.credentials;

	char ip[16];
	const char *reason;
	// Before the camera exists, a newer request replaces this one outright.
	while ((reason = hat_wifi_connect(credentials->ssid, credentials->pass, ip, sizeof(ip))) != NULL) {
		hat_pipeline_result_cb callback = hat_active_request.result_cb;
		hat_pipeline_request_t next;
		const hat_pipeline_state_t idle = HAT_PIPELINE_IDLE;
		bool replaced = hat_take_pending(&next, &idle);
		if (callback) callback(false, NULL, reason);
		if (!replaced) {
			vTaskDelete(NULL);
			return;
		}
		hat_active_request = next;
	}
	hat_wifi_remember(credentials);

	// Retain the bring-up delay as a diagnostic variable, not a claimed VOE fix.
	vTaskDelay(pdMS_TO_TICKS(1000));
	reason = hat_video_start();
	if (reason) {
		// SDK partial video initialization is not retryable in place: reboot
		// a bounded number of times, then latch FAILED with BLE still up.
		hat_pipeline_camera_fault(reason, true);
		vTaskDelete(NULL);
		return;
	}
	TickType_t camera_up_since = xTaskGetTickCount();
	bool camera_proven = false;

	taskENTER_CRITICAL();
	hat_pipeline_task_handle = xTaskGetCurrentTaskHandle();
	hat_pipeline_state = HAT_PIPELINE_RUNNING;
	taskEXIT_CRITICAL();
	if (hat_active_request.result_cb) {
		hat_active_request.result_cb(true, ip, NULL);
	}

	while (1) {
		// A switch request wakes the task early (or was queued during camera
		// bring-up); otherwise supervise periodically.
		if (!hat_request_pending()) ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(HAT_SUPERVISE_INTERVAL_MS));
		hat_pipeline_switch(ip, sizeof(ip));
		if (wifi_is_connected_to_ap() != RTW_SUCCESS) {
			// Recover only the last successful network, held in memory. A switch
			// request aborts this and runs next. RTMP reconnects independently
			// once association/DHCP are restored.
			const char *network_error = hat_wifi_connect(credentials->ssid, credentials->pass, ip, sizeof(ip));
			if (network_error && network_error != hat_superseded) {
				printf("\r\n[hat] network recovery: %s\r\n", network_error);
			}
		}
		if (hal_video_get_no_video_time() > HAT_NO_VIDEO_RESET_TIMEOUT_MS) {
			printf("\r\n[hat] no video frame for > %dms\r\n", HAT_NO_VIDEO_RESET_TIMEOUT_MS);
			hat_pipeline_camera_fault("video_stalled", false);
			vTaskDelete(NULL);
			return;
		}
		if (!camera_proven &&
			(TickType_t)(xTaskGetTickCount() - camera_up_since) >= pdMS_TO_TICKS(HAT_CAMERA_HEALTHY_MS)) {
			camera_proven = true;
			hat_camera_guard_healthy();
		}
	}
}

hat_pipeline_status_t hat_pipeline_status(void)
{
	taskENTER_CRITICAL();
	hat_pipeline_state_t state = hat_pipeline_state;
	bool pending = hat_switch_pending;
	taskEXIT_CRITICAL();
	switch (state) {
	case HAT_PIPELINE_STARTING:
		return HAT_PIPELINE_STATUS_CONNECTING;
	case HAT_PIPELINE_RUNNING:
		return pending ? HAT_PIPELINE_STATUS_CONNECTING : HAT_PIPELINE_STATUS_RUNNING;
	case HAT_PIPELINE_FAILED:
		return HAT_PIPELINE_STATUS_FAILED;
	default:
		return HAT_PIPELINE_STATUS_IDLE;
	}
}

static void hat_request_copy(hat_pipeline_request_t *dst, const char *ssid, const char *pass,
							 hat_pipeline_result_cb result_cb)
{
	memset(dst, 0, sizeof(*dst));
	strncpy(dst->credentials.ssid, ssid, sizeof(dst->credentials.ssid) - 1);
	strncpy(dst->credentials.pass, pass, sizeof(dst->credentials.pass) - 1);
	dst->result_cb = result_cb;
}

bool hat_pipeline_start(const char *ssid, const char *pass, hat_pipeline_result_cb result_cb)
{
	if (!ssid || !pass || strlen(ssid) >= HAT_WIFI_SSID_MAX_LEN || strlen(pass) >= HAT_WIFI_PASS_MAX_LEN) {
		return false;
	}
	hat_pipeline_request_t request;
	hat_request_copy(&request, ssid, pass, result_cb);

	// STARTING/RUNNING hand the request to the existing task: it replaces an
	// association still in progress, or runs as a switch once the camera is up.
	taskENTER_CRITICAL();
	hat_pipeline_state_t state = hat_pipeline_state;
	bool accepted = state == HAT_PIPELINE_IDLE ||
					((state == HAT_PIPELINE_STARTING || state == HAT_PIPELINE_RUNNING) && !hat_switch_pending);
	TaskHandle_t running_task = hat_pipeline_task_handle;
	if (accepted && state == HAT_PIPELINE_IDLE) {
		hat_pipeline_state = HAT_PIPELINE_STARTING;
	} else if (accepted) {
		hat_pending_request = request;
		hat_switch_pending = true;
	}
	taskEXIT_CRITICAL();
	if (!accepted) return false;

	if (state != HAT_PIPELINE_IDLE) {
		// STARTING polls the flag; a RUNNING task may be waiting for up to 10 s.
		if (state == HAT_PIPELINE_RUNNING) xTaskNotifyGive(running_task);
		return true;
	}

	hat_active_request = request;
	if (xTaskCreate(hat_pipeline_task, (const char *)"hat_pipeline", 4096, NULL, tskIDLE_PRIORITY + 1,
					NULL) != pdPASS) {
		printf("\r\n[hat] hat_pipeline_task: Create Task Error\r\n");
		taskENTER_CRITICAL();
		hat_pipeline_state = HAT_PIPELINE_IDLE;
		taskEXIT_CRITICAL();
		if (result_cb) result_cb(false, NULL, "pipeline_task_failed");
	}
	return true;
}
