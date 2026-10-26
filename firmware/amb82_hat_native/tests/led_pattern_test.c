// Host tests for the status indicator mapping (no GPIO involved).
#include <assert.h>
#include <stdio.h>
#include "../src/mmfv2_video_example/hat_led_pattern.c"

static hat_indicator_state_t state(hat_network_led_state_t network, hat_stream_led_state_t stream) {
    return (hat_indicator_state_t){ .network = network, .stream = stream };
}

// Counts ticks the given LED is lit over one 2-second cycle (16 ticks).
static int lit_ticks(const hat_indicator_state_t *s, bool blue) {
    int lit = 0;
    for (uint32_t tick = 0; tick < 16; tick++) {
        bool b, g;
        hat_led_pattern(s, tick, &b, &g);
        lit += blue ? b : g;
    }
    return lit;
}

int main(void) {
    assert(hat_stream_led_state("publishing") == HAT_STREAM_LED_LIVE);
    assert(hat_stream_led_state("connecting") == HAT_STREAM_LED_CONNECTING);
    assert(hat_stream_led_state("reconnecting") == HAT_STREAM_LED_CONNECTING);
    assert(hat_stream_led_state("idle") == HAT_STREAM_LED_OFF);
    assert(hat_stream_led_state("stopped") == HAT_STREAM_LED_OFF);
    assert(hat_stream_led_state(NULL) == HAT_STREAM_LED_OFF);

    // Blue: heartbeat while waiting, half duty while connecting, solid when connected.
    hat_indicator_state_t s = state(HAT_NETWORK_WAITING, HAT_STREAM_LED_OFF);
    assert(lit_ticks(&s, true) == 1);
    s = state(HAT_NETWORK_CONNECTING, HAT_STREAM_LED_OFF);
    assert(lit_ticks(&s, true) == 8);
    s = state(HAT_NETWORK_CONNECTED, HAT_STREAM_LED_OFF);
    assert(lit_ticks(&s, true) == 16);

    // Green follows the publisher independently of the network LED.
    assert(lit_ticks(&s, false) == 0);
    s = state(HAT_NETWORK_CONNECTED, HAT_STREAM_LED_CONNECTING);
    assert(lit_ticks(&s, false) == 8);
    s = state(HAT_NETWORK_CONNECTING, HAT_STREAM_LED_LIVE);
    assert(lit_ticks(&s, false) == 16);

    // Pairing mode: blue double-blinks (two flashes per second) whatever the
    // network state; green still reports the stream.
    s = state(HAT_NETWORK_CONNECTED, HAT_STREAM_LED_LIVE);
    s.pairing_open = true;
    assert(lit_ticks(&s, true) == 4);
    assert(lit_ticks(&s, false) == 16);

    // Fault: the two LEDs alternate and are never lit together; it beats pairing.
    s = state(HAT_NETWORK_FAULT, HAT_STREAM_LED_LIVE);
    s.pairing_open = true;
    for (uint32_t tick = 0; tick < 16; tick++) {
        bool b, g;
        hat_led_pattern(&s, tick, &b, &g);
        assert(b != g);
    }

    // Button-hold feedback overrides everything, including a fault.
    s.hold = HAT_HOLD_PAIRING_ARMED;
    assert(lit_ticks(&s, true) == 16 && lit_ticks(&s, false) == 16);
    s.hold = HAT_HOLD_RESET_ARMED;
    for (uint32_t tick = 0; tick < 16; tick++) {
        bool b, g;
        hat_led_pattern(&s, tick, &b, &g);
        assert(b == g); // blink together, unlike the fault pattern
    }
    assert(lit_ticks(&s, true) == 8);

    puts("LED pattern tests passed");
    return 0;
}
