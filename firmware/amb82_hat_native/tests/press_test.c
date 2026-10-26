// Host tests for button gesture classification.
#include <assert.h>
#include <stdio.h>
#include "../src/mmfv2_video_example/hat_press.c"

static hat_press_t press;
static uint32_t now;

// Samples the control every 10 ms, like the firmware's 20 ms poll but finer.
static hat_press_event_t hold(bool pressed, uint32_t duration_ms) {
    hat_press_event_t seen = HAT_PRESS_NONE;
    for (uint32_t t = 0; t < duration_ms; t += 10) {
        hat_press_event_t event = hat_press_update(&press, pressed, now);
        if (event != HAT_PRESS_NONE) { assert(seen == HAT_PRESS_NONE); seen = event; }
        now += 10;
    }
    return seen;
}
static hat_press_event_t gesture(uint32_t held_ms) {
    assert(hold(true, held_ms) == HAT_PRESS_NONE); // actions fire only on release
    return hold(false, 200);
}

int main(void) {
    now = 1000;
    hat_press_init(&press, false, now);
    assert(hold(false, 200) == HAT_PRESS_NONE);

    assert(gesture(200) == HAT_PRESS_SHORT);
    assert(gesture(1500) == HAT_PRESS_NONE);   // ambiguous: ignored
    assert(gesture(3500) == HAT_PRESS_PAIRING);
    assert(gesture(12000) == HAT_PRESS_FACTORY_RESET);

    // Bounces shorter than the debounce window are not presses.
    for (int i = 0; i < 5; i++) { hold(true, 10); hold(false, 10); }
    assert(hold(false, 200) == HAT_PRESS_NONE);

    // Hold-stage feedback tracks the action a release would take.
    hold(true, 100);
    assert(hat_press_hold_stage(&press, now) == HAT_HOLD_NONE);
    hold(true, 3000);
    assert(hat_press_hold_stage(&press, now) == HAT_HOLD_PAIRING_ARMED);
    hold(true, 7000);
    assert(hat_press_hold_stage(&press, now) == HAT_HOLD_RESET_ARMED);
    assert(hold(false, 200) == HAT_PRESS_FACTORY_RESET);
    assert(hat_press_hold_stage(&press, now) == HAT_HOLD_NONE);

    // A control held at boot is ignored until released, however long.
    hat_press_init(&press, true, now);
    assert(hold(true, 15000) == HAT_PRESS_NONE);
    assert(hat_press_hold_stage(&press, now) == HAT_HOLD_NONE);
    assert(hold(false, 200) == HAT_PRESS_NONE);
    assert(gesture(200) == HAT_PRESS_SHORT); // normal afterwards

    // Clock wraparound mid-hold still measures correctly.
    now = UINT32_MAX - 1000;
    hat_press_init(&press, false, now);
    hold(false, 100);
    assert(gesture(3500) == HAT_PRESS_PAIRING);

    puts("Press tests passed");
    return 0;
}
