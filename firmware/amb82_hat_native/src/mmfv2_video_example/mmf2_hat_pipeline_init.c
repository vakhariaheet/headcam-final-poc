// BLE-provisioned Wi-Fi and H.264 capture into an outbound RTMP sink.
// Frames are discarded while idle; no local streaming server is opened.

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
#include "wifi_conf.h"
#include "lwip_netconf.h"

#include "mmf2_hat_pipeline_init.h"

#define HAT_VIDEO_CHANNEL 0
#define HAT_VIDEO_BPS (2 * 1024 * 1024)
#define HAT_VIDEO_RCMODE 2 // 1: CBR, 2: VBR
#define HAT_WIFI_CONNECT_TIMEOUT_MS (30 * 1000)
#define HAT_NO_VIDEO_RESET_TIMEOUT_MS (30 * 1000)
#define HAT_SSID_MAX_LEN 33
#define HAT_PASS_MAX_LEN 65

typedef struct {
	char ssid[HAT_SSID_MAX_LEN];
	char pass[HAT_PASS_MAX_LEN];
	hat_pipeline_result_cb result_cb;
} hat_pipeline_task_params_t;

static hat_pipeline_task_params_t hat_task_params;
static bool hat_pipeline_active;

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

// Association uses the asynchronous SDK API so the 30-second deadline includes
// the handshake itself. DHCP has its own SDK timeout and must succeed separately.
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
	printf("\r\n[hat] Camera ready; cloud publisher idle (no local RTSP server)\r\n");
	return NULL;
}

static void hat_pipeline_task(void *param)
{
	hat_pipeline_task_params_t *params = (hat_pipeline_task_params_t *)param;

	char ip[16];
	const char *reason = hat_wifi_connect(params->ssid, params->pass, ip, sizeof(ip));
	if (reason) {
		hat_pipeline_result_cb callback = params->result_cb;
		taskENTER_CRITICAL();
		hat_pipeline_active = false;
		taskEXIT_CRITICAL();
		if (callback) callback(false, NULL, reason);
		vTaskDelete(NULL);
		return;
	}

	// Retain the bring-up delay as a diagnostic variable, not a claimed VOE fix.
	vTaskDelay(pdMS_TO_TICKS(1000));
	reason = hat_video_start();
	if (reason) {
		printf("\r\n[hat] %s; reset required before another camera attempt\r\n", reason);
		if (params->result_cb) params->result_cb(false, NULL, reason);
		// Latch the failed pipeline: SDK partial video initialization is not
		// safely retryable. Keep BLE/serial alive for diagnosis; no reboot loop.
		vTaskDelete(NULL);
		return;
	}

	if (params->result_cb) {
		params->result_cb(true, ip, NULL);
	}

	while (1) {
		vTaskDelay(pdMS_TO_TICKS(10000));
		if (wifi_is_connected_to_ap() != RTW_SUCCESS) {
			// Recover only the explicitly provisioned in-memory credentials.
			// RTMP reconnects independently once association/DHCP are restored.
			const char *network_error = hat_wifi_connect(params->ssid, params->pass, ip, sizeof(ip));
			if (network_error) printf("\r\n[hat] network recovery: %s\r\n", network_error);
		}
		if (hal_video_get_no_video_time() > HAT_NO_VIDEO_RESET_TIMEOUT_MS) {
			printf("\r\n[hat] no video frame for > %dms; reset required\r\n", HAT_NO_VIDEO_RESET_TIMEOUT_MS);
			vTaskDelete(NULL);
			return;
		}
	}
}

bool hat_pipeline_start(const char *ssid, const char *pass, hat_pipeline_result_cb result_cb)
{
	taskENTER_CRITICAL();
	bool available = !hat_pipeline_active;
	if (available) hat_pipeline_active = true;
	taskEXIT_CRITICAL();
	if (!available) return false;

	strncpy(hat_task_params.ssid, ssid, sizeof(hat_task_params.ssid) - 1);
	hat_task_params.ssid[sizeof(hat_task_params.ssid) - 1] = '\0';
	strncpy(hat_task_params.pass, pass, sizeof(hat_task_params.pass) - 1);
	hat_task_params.pass[sizeof(hat_task_params.pass) - 1] = '\0';
	hat_task_params.result_cb = result_cb;

	if (xTaskCreate(hat_pipeline_task, (const char *)"hat_pipeline", 4096, &hat_task_params, tskIDLE_PRIORITY + 1,
					NULL) != pdPASS) {
		printf("\r\n[hat] hat_pipeline_task: Create Task Error\r\n");
		taskENTER_CRITICAL();
		hat_pipeline_active = false;
		taskEXIT_CRITICAL();
		if (result_cb) result_cb(false, NULL, "pipeline_task_failed");
	}
	return true;
}
