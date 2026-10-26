#pragma once
#include <stdbool.h>
#include <stdint.h>

// Classifies a single physical control (onboard button today; a custom
// button or capacitive pad later) into gestures. Hardware-independent: feed
// it debounced-or-raw samples and a millisecond clock. Actions fire on
// release, so holding toward a factory reset never passes through pairing.
//
//   release before 1 s        short press
//   release after 3 s         enter pairing mode
//   release after 10 s        factory reset
//   release between 1 and 3 s ignored (likely accidental)

#define HAT_PRESS_DEBOUNCE_MS 30
#define HAT_PRESS_SHORT_MAX_MS 1000
#define HAT_PRESS_PAIRING_MS 3000
#define HAT_PRESS_RESET_MS 10000

typedef enum {
	HAT_PRESS_NONE,
	HAT_PRESS_SHORT,
	HAT_PRESS_PAIRING,
	HAT_PRESS_FACTORY_RESET,
} hat_press_event_t;

// What releasing now would do; drives LED feedback while held.
typedef enum {
	HAT_HOLD_NONE,
	HAT_HOLD_PAIRING_ARMED,
	HAT_HOLD_RESET_ARMED,
} hat_hold_stage_t;

typedef struct {
	bool wait_release;
	bool stable_pressed;
	bool last_raw;
	uint32_t raw_changed_at;
	uint32_t pressed_at;
} hat_press_t;

void hat_press_init(hat_press_t *press, bool raw_pressed, uint32_t now_ms);
hat_press_event_t hat_press_update(hat_press_t *press, bool raw_pressed, uint32_t now_ms);
hat_hold_stage_t hat_press_hold_stage(const hat_press_t *press, uint32_t now_ms);
