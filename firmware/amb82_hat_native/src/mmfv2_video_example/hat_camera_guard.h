#pragma once
#include <stdbool.h>
#include <stdint.h>

// Bounded recovery from camera failures. The SDK's partial video init is not
// retryable in place, so a failed or stalled camera reboots the hat, at most
// HAT_CAMERA_MAX_RESTARTS times in a row. A streak ends once the camera runs
// for HAT_CAMERA_HEALTHY_MS. After the last restart the hat stays up with the
// fault LED until someone power-cycles it, which starts a fresh streak.
// The streak lives in FTL after the owner record so it survives the reboots.

#define HAT_CAMERA_MAX_RESTARTS 3
#define HAT_CAMERA_HEALTHY_MS (10u * 60u * 1000u)

typedef enum {
	HAT_CAMERA_RESTART, // reboot now; the streak was saved
	HAT_CAMERA_STOP,    // give up and wait for a power cycle
} hat_camera_action_t;

// Call once at boot, after FTL init.
void hat_camera_guard_boot(void);
// Records a failure and decides what to do. Stops instead of rebooting when
// the streak cannot be saved, so a flash fault cannot cause a reboot loop.
hat_camera_action_t hat_camera_guard_fault(void);
// The camera has run for HAT_CAMERA_HEALTHY_MS: ends the streak.
void hat_camera_guard_healthy(void);
// Automatic restarts in the current streak, for status reporting.
uint8_t hat_camera_guard_restarts(void);
// True once the hat has given up on the camera this boot.
bool hat_camera_guard_stopped(void);
