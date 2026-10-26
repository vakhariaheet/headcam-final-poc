// Host tests for the saved Wi-Fi record against an in-memory FTL.
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../src/mmfv2_video_example/hat_wifi_store.c"

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

int main(void) {
    hat_wifi_credentials_t loaded;
    memset(flash, 0xff, sizeof(flash)); // erased flash
    assert(!hat_wifi_store_load(&loaded));

    assert(hat_wifi_store_save("test-network", "test-password") && saves == 1);
    assert(hat_wifi_store_load(&loaded));
    assert(strcmp(loaded.ssid, "test-network") == 0 && strcmp(loaded.pass, "test-password") == 0);
    assert(hat_wifi_store_save("test-network", "test-password") && saves == 1); // unchanged: no write

    assert(hat_wifi_store_save("open-network", "") && saves == 2);
    assert(hat_wifi_store_load(&loaded) && loaded.pass[0] == '\0');

    char longest_ssid[33]; memset(longest_ssid, 's', 32); longest_ssid[32] = 0;
    char longest_pass[65]; memset(longest_pass, 'p', 64); longest_pass[64] = 0;
    assert(hat_wifi_store_save(longest_ssid, longest_pass));
    assert(hat_wifi_store_load(&loaded) && strlen(loaded.ssid) == 32 && strlen(loaded.pass) == 64);

    char too_long[34]; memset(too_long, 's', 33); too_long[33] = 0;
    assert(!hat_wifi_store_save(too_long, "test-password"));
    assert(!hat_wifi_store_save("", "test-password"));

    flash[20] ^= 0x01; // corrupt a stored byte
    assert(!hat_wifi_store_load(&loaded));

    assert(hat_wifi_store_save("test-network", "test-password"));
    assert(hat_wifi_store_clear() && !hat_wifi_store_load(&loaded));

    fail_io = true;
    assert(!hat_wifi_store_save("test-network", "test-password"));
    assert(!hat_wifi_store_load(&loaded));
    puts("Wi-Fi store tests passed");
    return 0;
}
