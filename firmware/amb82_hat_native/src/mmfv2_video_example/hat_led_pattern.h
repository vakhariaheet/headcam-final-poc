#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "hat_press.h"

// Pure indicator mapping, kept separate from GPIO so host tests can run it.
// hat_indicator_state_t is the hardware-neutral input; a future RGB LED can
// render the same state with colors instead of these two-LED patterns.
//
// Highest priority first:
//   Button held 3-10 s:  both solid             release now to enter pairing
//   Button held 10 s+:   both fast, together    release now to factory reset
//   Camera fault:        both alternate (2 Hz)  reset required
//   Pairing mode:        blue double-blink      ready for a phone to claim
//   Blue (network):      short blink every 2 s  waiting for Wi-Fi provisioning
//                        fast blink (4 Hz)      associating, switching, or recovering
//                        solid                  Wi-Fi connected
//   Green (stream):      off / fast blink / solid = idle / RTMP connecting / publishing
// Pairing mode only replaces the blue pattern; green keeps showing the stream.

#define HAT_LED_TICK_MS 125

typedef enum {
	HAT_NETWORK_WAITING,    // no request in progress
	HAT_NETWORK_CONNECTING, // association/DHCP, a pending switch, or recovery
	HAT_NETWORK_CONNECTED,
	HAT_NETWORK_FAULT,      // camera failed; reset required
} hat_network_led_state_t;

typedef enum {
	HAT_STREAM_LED_OFF,
	HAT_STREAM_LED_CONNECTING,
	HAT_STREAM_LED_LIVE,
} hat_stream_led_state_t;

typedef struct {
	hat_network_led_state_t network;
	hat_stream_led_state_t stream;
	bool pairing_open;
	hat_hold_stage_t hold;
} hat_indicator_state_t;

// Maps a publisher state string from hat_stream_stats().
hat_stream_led_state_t hat_stream_led_state(const char *stream_state);

// tick counts HAT_LED_TICK_MS periods.
void hat_led_pattern(const hat_indicator_state_t *state, uint32_t tick, bool *blue_on, bool *green_on);
