#pragma once
#include <stdbool.h>

#define HAT_WIFI_SSID_MAX_LEN 33 // includes terminator
#define HAT_WIFI_PASS_MAX_LEN 65 // includes terminator

typedef struct {
	char ssid[HAT_WIFI_SSID_MAX_LEN];
	char pass[HAT_WIFI_PASS_MAX_LEN];
} hat_wifi_credentials_t;

// Last network that completed association + DHCP, kept in the BT stack's FTL
// application area (offsets above the stack's own bond records). Stored in
// plaintext: anyone with flash access can read it.
bool hat_wifi_store_load(hat_wifi_credentials_t *out);
// Skips the flash write when the stored record already matches.
bool hat_wifi_store_save(const char *ssid, const char *pass);
bool hat_wifi_store_clear(void);
