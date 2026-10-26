// Physical controls and status display: one 25 ms task polls the button,
// drives pairing-mode and authentication timeouts, and renders the LEDs
// every fifth tick from existing pipeline/stream state.

#include <stdio.h>

#include "FreeRTOS.h"
#include "task.h"
#include "sys_api.h"
#include "wifi_conf.h"

#include "ble_provisioning_init.h"
#include "hat_button.h"
#include "hat_camera_guard.h"
#include "hat_control.h"
#include "hat_led.h"
#include "hat_led_pattern.h"
#include "hat_owner.h"
#include "hat_pairing.h"
#include "hat_press.h"
#include "hat_wifi_store.h"
#include "mmf2_hat_pipeline_init.h"
#include "module_hat_rtmp.h"

#define HAT_CONTROL_TICK_MS 25
#define HAT_CONTROL_LED_EVERY (HAT_LED_TICK_MS / HAT_CONTROL_TICK_MS)

static uint32_t hat_now_ms(void)
{
	return (uint32_t)xTaskGetTickCount() * portTICK_PERIOD_MS;
}

static hat_network_led_state_t hat_control_network_state(void)
{
	switch (hat_pipeline_status()) {
	case HAT_PIPELINE_STATUS_FAILED:
		return HAT_NETWORK_FAULT;
	case HAT_PIPELINE_STATUS_CONNECTING:
		return HAT_NETWORK_CONNECTING;
	case HAT_PIPELINE_STATUS_RUNNING:
		// The supervisor reconnects in the background when association drops.
		return wifi_is_connected_to_ap() == RTW_SUCCESS ? HAT_NETWORK_CONNECTED : HAT_NETWORK_CONNECTING;
	default:
		return HAT_NETWORK_WAITING;
	}
}

// Physical access is the authority: forget Wi-Fi and owner, then reboot
// into pairing mode.
static void hat_factory_reset(void)
{
	printf("\r\n[hat] factory reset: clearing Wi-Fi and owner, rebooting\r\n");
	hat_led_render(true, true);
	if (!hat_wifi_store_clear()) printf("\r\n[hat] factory reset: Wi-Fi clear failed\r\n");
	if (!hat_owner_clear()) printf("\r\n[hat] factory reset: owner clear failed\r\n");
	vTaskDelay(pdMS_TO_TICKS(500));
	sys_reset();
}

static void hat_control_handle_press(hat_press_event_t event, uint32_t now)
{
	switch (event) {
	case HAT_PRESS_SHORT:
		if (hat_pairing_is_open()) {
			printf("\r\n[hat] pairing mode closed by button\r\n");
			hat_pairing_close(now);
		}
		break;
	case HAT_PRESS_PAIRING:
		printf("\r\n[hat] pairing mode open for %u s\r\n", (unsigned)(HAT_PAIRING_WINDOW_MS / 1000));
		hat_pairing_open(now);
		break;
	case HAT_PRESS_FACTORY_RESET:
		hat_factory_reset();
		break;
	default:
		break;
	}
}

static void hat_control_task(void *param)
{
	(void)param;
	hat_press_t press;
	hat_press_init(&press, hat_button_pressed(), hat_now_ms());
	uint32_t advertised_generation = hat_pairing_generation();
	uint32_t led_tick = 0;
	bool was_open = hat_pairing_is_open();

	for (uint32_t loop = 0;; loop++) {
		uint32_t now = hat_now_ms();
		hat_control_handle_press(hat_press_update(&press, hat_button_pressed(), now), now);

		uint8_t stale = hat_pairing_tick(now);
		if (stale != HAT_NO_CONNECTION) {
			printf("\r\n[hat] disconnecting link that did not authenticate\r\n");
			ble_provisioning_disconnect(stale);
		}
		uint32_t generation = hat_pairing_generation();
		if (generation != advertised_generation) {
			advertised_generation = generation;
			bool open = hat_pairing_is_open();
			if (was_open && !open) printf("\r\n[hat] pairing mode closed\r\n");
			was_open = open;
			ble_provisioning_refresh_advertising();
		}

		if (loop % HAT_CONTROL_LED_EVERY == 0) {
			uint32_t sent_bytes;
			const char *stream_state;
			hat_stream_stats(&sent_bytes, &stream_state);
			hat_indicator_state_t indicator = {
				.network = hat_control_network_state(),
				.stream = hat_stream_led_state(stream_state),
				.pairing_open = hat_pairing_is_open(),
				.hold = hat_press_hold_stage(&press, now),
			};
			bool blue_on, green_on;
			hat_led_pattern(&indicator, led_tick++, &blue_on, &green_on);
			hat_led_render(blue_on, green_on);
		}
		vTaskDelay(pdMS_TO_TICKS(HAT_CONTROL_TICK_MS));
	}
}

void hat_control_start(void)
{
	hat_owner_load();
	hat_camera_guard_boot();
	if (hat_camera_guard_restarts() > 0) {
		printf("\r\n[hat] recovering from camera fault: restart %u of %u\r\n",
			   (unsigned)hat_camera_guard_restarts(), (unsigned)HAT_CAMERA_MAX_RESTARTS);
	}
	bool owned = hat_owner_exists();
	hat_pairing_init(owned, hat_now_ms());
	printf("\r\n[hat] %s\r\n", owned ? "owner key present; pairing mode closed (hold button 3 s to open)"
						: "no owner; pairing mode open");
	hat_led_init();
	hat_button_init();
	if (xTaskCreate(hat_control_task, (const char *)"hat_control", 1024, NULL, tskIDLE_PRIORITY + 2, NULL) != pdPASS) {
		printf("\r\n[hat] control task create failed; button and LEDs disabled\r\n");
	}
}
