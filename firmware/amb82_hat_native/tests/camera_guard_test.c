// Host tests for the camera restart streak against an in-memory FTL.
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../src/mmfv2_video_example/hat_camera_guard.c"

static uint8_t flash[1024];
static int saves;
static bool fail_io;

uint32_t ftl_save(void *data, uint16_t offset, uint16_t size) {
    assert(offset % 4 == 0 && size % 4 == 0 && offset + size <= sizeof(flash));
    if (fail_io) return 1;
    memcpy(flash + offset, data, size); saves++; return 0;
}
uint32_t ftl_load(void *data, uint16_t offset, uint16_t size) {
    assert(offset % 4 == 0 && size % 4 == 0 && offset + size <= sizeof(flash));
    if (fail_io) return 1;
    memcpy(data, flash + offset, size); return 0;
}

// Simulates sys_reset(): RAM state is lost, flash survives.
static void reboot(void) {
    hat_camera_restarts = 0xAA;
    hat_camera_stopped = true;
    hat_camera_guard_boot();
}

int main(void) {
    memset(flash, 0xff, sizeof(flash)); // erased flash: no streak
    reboot();
    assert(hat_camera_guard_restarts() == 0 && !hat_camera_guard_stopped());

    // Up to three automatic restarts, each surviving the reboot it causes.
    for (int i = 1; i <= HAT_CAMERA_MAX_RESTARTS; i++) {
        assert(hat_camera_guard_fault() == HAT_CAMERA_RESTART);
        reboot();
        assert(hat_camera_guard_restarts() == i && !hat_camera_guard_stopped());
    }
    // The fourth failure gives up and stays up.
    assert(hat_camera_guard_fault() == HAT_CAMERA_STOP);
    assert(hat_camera_guard_stopped() && hat_camera_guard_restarts() == HAT_CAMERA_MAX_RESTARTS);

    // A power cycle after giving up starts a fresh streak.
    reboot();
    assert(hat_camera_guard_restarts() == 0 && !hat_camera_guard_stopped());
    assert(hat_camera_guard_fault() == HAT_CAMERA_RESTART);
    reboot();
    assert(hat_camera_guard_restarts() == 1);

    // Ten healthy minutes end the streak; with no streak there is no write.
    hat_camera_guard_healthy();
    reboot();
    assert(hat_camera_guard_restarts() == 0);
    int before = saves;
    hat_camera_guard_healthy();
    assert(saves == before);

    // A power cycle mid-streak (not after giving up) keeps the count.
    assert(hat_camera_guard_fault() == HAT_CAMERA_RESTART);
    assert(hat_camera_guard_fault() == HAT_CAMERA_RESTART);
    reboot();
    assert(hat_camera_guard_restarts() == 2);

    // A streak that cannot be saved stops instead of rebooting blindly.
    fail_io = true;
    assert(hat_camera_guard_fault() == HAT_CAMERA_STOP && hat_camera_guard_stopped());
    fail_io = false;

    // Corrupt or out-of-range records read as no streak.
    hat_camera_record_t bad = { HAT_CAMERA_STORE_MAGIC, HAT_CAMERA_STORE_VERSION, 9, 0 };
    memcpy(flash + HAT_CAMERA_STORE_OFFSET, &bad, sizeof(bad));
    reboot();
    assert(hat_camera_guard_restarts() == 0);
    bad.restarts = 1; bad.magic ^= 1;
    memcpy(flash + HAT_CAMERA_STORE_OFFSET, &bad, sizeof(bad));
    reboot();
    assert(hat_camera_guard_restarts() == 0);

    // Unreadable flash: no streak, and no crash.
    fail_io = true;
    reboot();
    assert(hat_camera_guard_restarts() == 0 && !hat_camera_guard_stopped());
    fail_io = false;

    // Does not overlap the owner record (offset 128, 44 bytes).
    assert(HAT_CAMERA_STORE_OFFSET >= 128 + 44);

    printf("camera guard tests passed\n");
    return 0;
}
