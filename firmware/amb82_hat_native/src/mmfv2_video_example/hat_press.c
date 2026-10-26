#include "hat_press.h"

void hat_press_init(hat_press_t *press, bool raw_pressed, uint32_t now_ms)
{
	press->stable_pressed = false;
	press->last_raw = false;
	press->raw_changed_at = now_ms;
	press->pressed_at = now_ms;
	// A control held during boot is ignored until released, so a stuck
	// button cannot trigger an action on power-up.
	press->wait_release = raw_pressed;
}

hat_press_event_t hat_press_update(hat_press_t *press, bool raw_pressed, uint32_t now_ms)
{
	if (press->wait_release) {
		if (!raw_pressed) {
			press->wait_release = false;
			press->raw_changed_at = now_ms;
		}
		return HAT_PRESS_NONE;
	}
	if (raw_pressed != press->last_raw) {
		press->last_raw = raw_pressed;
		press->raw_changed_at = now_ms;
		return HAT_PRESS_NONE;
	}
	if ((uint32_t)(now_ms - press->raw_changed_at) < HAT_PRESS_DEBOUNCE_MS || raw_pressed == press->stable_pressed) {
		return HAT_PRESS_NONE;
	}

	// The raw level has been steady for the debounce period: accept it,
	// timestamped from when it first changed.
	press->stable_pressed = raw_pressed;
	if (raw_pressed) {
		press->pressed_at = press->raw_changed_at;
		return HAT_PRESS_NONE;
	}
	uint32_t held = press->raw_changed_at - press->pressed_at;
	if (held >= HAT_PRESS_RESET_MS) return HAT_PRESS_FACTORY_RESET;
	if (held >= HAT_PRESS_PAIRING_MS) return HAT_PRESS_PAIRING;
	if (held < HAT_PRESS_SHORT_MAX_MS) return HAT_PRESS_SHORT;
	return HAT_PRESS_NONE;
}

hat_hold_stage_t hat_press_hold_stage(const hat_press_t *press, uint32_t now_ms)
{
	if (!press->stable_pressed) return HAT_HOLD_NONE;
	uint32_t held = now_ms - press->pressed_at;
	if (held >= HAT_PRESS_RESET_MS) return HAT_HOLD_RESET_ARMED;
	if (held >= HAT_PRESS_PAIRING_MS) return HAT_HOLD_PAIRING_ARMED;
	return HAT_HOLD_NONE;
}
