// Camera restart streak, persisted after hat_owner.c's record (offset 128,
// 44 bytes) in the BT library's FTL application area.

#include <string.h>

#include "ftl_app.h"
#include "hat_camera_guard.h"

#define HAT_CAMERA_STORE_OFFSET 176
#define HAT_CAMERA_STORE_MAGIC 0x48415443u // "HATC"
#define HAT_CAMERA_STORE_VERSION 1u

typedef struct {
	uint32_t magic;
	uint32_t version;
	uint32_t restarts;
	uint32_t gave_up; // nonzero: the last boot stopped, so this boot is a manual power cycle
} hat_camera_record_t;

_Static_assert(sizeof(hat_camera_record_t) % 4 == 0, "FTL requires 4-byte multiples");

// Written by the pipeline task; byte-sized reads from BLE callbacks.
static volatile uint8_t hat_camera_restarts;
static volatile bool hat_camera_stopped;

static bool hat_camera_save(uint32_t restarts, bool gave_up)
{
	hat_camera_record_t record = {
		.magic = HAT_CAMERA_STORE_MAGIC,
		.version = HAT_CAMERA_STORE_VERSION,
		.restarts = restarts,
		.gave_up = gave_up ? 1u : 0u,
	};
	return ftl_save(&record, HAT_CAMERA_STORE_OFFSET, sizeof(record)) == 0;
}

void hat_camera_guard_boot(void)
{
	hat_camera_record_t record;
	bool valid = ftl_load(&record, HAT_CAMERA_STORE_OFFSET, sizeof(record)) == 0 &&
				 record.magic == HAT_CAMERA_STORE_MAGIC && record.version == HAT_CAMERA_STORE_VERSION &&
				 record.restarts <= HAT_CAMERA_MAX_RESTARTS;
	hat_camera_stopped = false;
	if (!valid) {
		hat_camera_restarts = 0;
		return;
	}
	if (record.gave_up) {
		// Only a person restarts a hat that gave up: give the camera fresh attempts.
		hat_camera_restarts = 0;
		hat_camera_save(0, false);
		return;
	}
	hat_camera_restarts = (uint8_t)record.restarts;
}

hat_camera_action_t hat_camera_guard_fault(void)
{
	uint8_t restarts = hat_camera_restarts;
	if (restarts < HAT_CAMERA_MAX_RESTARTS && hat_camera_save(restarts + 1u, false)) {
		hat_camera_restarts = restarts + 1u;
		return HAT_CAMERA_RESTART;
	}
	// Best effort: if this write fails too, the next boot simply resumes the
	// streak and stops at the limit again.
	hat_camera_save(restarts, true);
	hat_camera_stopped = true;
	return HAT_CAMERA_STOP;
}

void hat_camera_guard_healthy(void)
{
	if (hat_camera_restarts == 0) return;
	if (hat_camera_save(0, false)) hat_camera_restarts = 0;
}

uint8_t hat_camera_guard_restarts(void)
{
	return hat_camera_restarts;
}

bool hat_camera_guard_stopped(void)
{
	return hat_camera_stopped;
}
