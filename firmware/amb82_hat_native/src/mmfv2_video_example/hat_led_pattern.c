#include <string.h>

#include "hat_led_pattern.h"

#define HAT_LED_FAST_PERIOD_TICKS 2     // 250 ms on/off = 4 Hz toggle
#define HAT_LED_FAULT_PERIOD_TICKS 4    // 500 ms per LED
#define HAT_LED_HEARTBEAT_TICKS 16      // 2 s cycle
#define HAT_LED_HEARTBEAT_ON_TICKS 1    // 125 ms flash
#define HAT_LED_DOUBLE_BLINK_TICKS 8    // 1 s cycle: on, off, on, then dark

hat_stream_led_state_t hat_stream_led_state(const char *stream_state)
{
	if (!stream_state) return HAT_STREAM_LED_OFF;
	if (strcmp(stream_state, "publishing") == 0) return HAT_STREAM_LED_LIVE;
	if (strcmp(stream_state, "connecting") == 0 || strcmp(stream_state, "reconnecting") == 0) {
		return HAT_STREAM_LED_CONNECTING;
	}
	return HAT_STREAM_LED_OFF;
}

static bool hat_led_fast(uint32_t tick)
{
	return (tick / HAT_LED_FAST_PERIOD_TICKS) % 2 == 0;
}

void hat_led_pattern(const hat_indicator_state_t *state, uint32_t tick, bool *blue_on, bool *green_on)
{
	if (state->hold == HAT_HOLD_RESET_ARMED) {
		*blue_on = *green_on = hat_led_fast(tick);
		return;
	}
	if (state->hold == HAT_HOLD_PAIRING_ARMED) {
		*blue_on = *green_on = true;
		return;
	}
	if (state->network == HAT_NETWORK_FAULT) {
		bool phase = (tick / HAT_LED_FAULT_PERIOD_TICKS) % 2 == 0;
		*blue_on = phase;
		*green_on = !phase;
		return;
	}

	if (state->pairing_open) {
		uint32_t phase = tick % HAT_LED_DOUBLE_BLINK_TICKS;
		*blue_on = phase == 0 || phase == 2;
	} else {
		switch (state->network) {
		case HAT_NETWORK_CONNECTED:
			*blue_on = true;
			break;
		case HAT_NETWORK_CONNECTING:
			*blue_on = hat_led_fast(tick);
			break;
		default:
			*blue_on = tick % HAT_LED_HEARTBEAT_TICKS < HAT_LED_HEARTBEAT_ON_TICKS;
			break;
		}
	}

	switch (state->stream) {
	case HAT_STREAM_LED_LIVE:
		*green_on = true;
		break;
	case HAT_STREAM_LED_CONNECTING:
		*green_on = hat_led_fast(tick);
		break;
	default:
		*green_on = false;
		break;
	}
}
