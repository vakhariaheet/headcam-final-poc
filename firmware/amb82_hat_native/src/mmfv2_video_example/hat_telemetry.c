// Periodic BLE telemetry: {"event":"telemetry",...} on FFE2. Samples are not
// cached as the FFE2 read value, so a read still returns the last status.

#include <stdio.h>

#include "FreeRTOS.h"
#include "task.h"
#include "module_video.h"
#include "wifi_conf.h"

#include "ble_provisioning_service.h"
#include "hat_telemetry.h"
#include "module_hat_rtmp.h"

#define HAT_TELEMETRY_INTERVAL_MS 2000
#define HAT_TELEMETRY_JSON_MAX_LEN 128

typedef struct {
	mm_context_t *video_ctx;
	int video_channel;
} hat_telemetry_source_t;

static hat_telemetry_source_t hat_telemetry_source;
static bool hat_telemetry_started;

static void hat_telemetry_task(void *param)
{
	hat_telemetry_source_t *source = (hat_telemetry_source_t *)param;
	uint32_t previous_bytes;
	const char *state;
	hat_stream_stats(&previous_bytes, &state);
	TickType_t previous_tick = xTaskGetTickCount();

	while (1) {
		vTaskDelay(pdMS_TO_TICKS(HAT_TELEMETRY_INTERVAL_MS));

		uint32_t sent_bytes;
		hat_stream_stats(&sent_bytes, &state);
		TickType_t now = xTaskGetTickCount();
		uint32_t elapsed_ms = (uint32_t)(now - previous_tick) * portTICK_PERIOD_MS;
		uint32_t tx_kbps = elapsed_ms ? (uint32_t)((uint64_t)(sent_bytes - previous_bytes) * 8 / elapsed_ms) : 0;
		previous_bytes = sent_bytes;
		previous_tick = now;

		uint32_t encoder_bps = 0;
		mm_module_ctrl(source->video_ctx, CMD_VIDEO_GET_CURRENT_BITRATE, (int)&encoder_bps);
		int fps = video_get_cb_fps(source->video_channel);

		char rssi[8] = "null";
		rtw_phy_statistics_t phy;
		if (wifi_is_connected_to_ap() == RTW_SUCCESS && wifi_fetch_phy_statistic(&phy) == RTW_SUCCESS) {
			snprintf(rssi, sizeof(rssi), "%d", phy.rssi);
		}

		char json[HAT_TELEMETRY_JSON_MAX_LEN];
		int len = snprintf(json, sizeof(json),
						   "{\"event\":\"telemetry\",\"kbps\":%u,\"tx_kbps\":%u,\"fps\":%d,\"rssi\":%s,\"stream\":\"%s\"}",
						   (unsigned)(encoder_bps / 1000), (unsigned)tx_kbps, fps, rssi, state);
		if (len > 0 && (size_t)len < sizeof(json)) {
			ble_provisioning_service_notify_event(json, (uint16_t)len);
		}
	}
}

void hat_telemetry_start(mm_context_t *video_ctx, int video_channel)
{
	if (hat_telemetry_started) return;
	hat_telemetry_source.video_ctx = video_ctx;
	hat_telemetry_source.video_channel = video_channel;
	if (xTaskCreate(hat_telemetry_task, (const char *)"hat_telemetry", 1024, &hat_telemetry_source,
					tskIDLE_PRIORITY + 1, NULL) != pdPASS) {
		printf("\r\n[hat] telemetry task create failed; continuing without telemetry\r\n");
		return;
	}
	hat_telemetry_started = true;
}
