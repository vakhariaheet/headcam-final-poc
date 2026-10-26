#pragma once
#include <stdbool.h>
#include <stdint.h>

#define HAT_OWNER_KEY_LEN 32
#define HAT_AUTH_NONCE_LEN 16
#define HAT_AUTH_MAC_LEN 32

// The single owner's shared key, derived by both sides during a claim (see
// hat_secure.h) and kept in FTL after the Wi-Fi record. Plaintext in flash.
// A new claim replaces the previous owner.

// Loads the stored key into memory. Call once at boot, after FTL init.
void hat_owner_load(void);
bool hat_owner_exists(void);
// Persists key as the owner, replacing any previous owner.
bool hat_owner_save(const uint8_t key[HAT_OWNER_KEY_LEN]);
bool hat_owner_clear(void);
// True when mac == HMAC-SHA256(owner key, nonce). Constant time.
bool hat_owner_verify(const uint8_t nonce[HAT_AUTH_NONCE_LEN], const uint8_t mac[HAT_AUTH_MAC_LEN]);
// Derives the session key for a link that proved ownership with nonce.
bool hat_owner_session_key(const uint8_t nonce[HAT_AUTH_NONCE_LEN], uint8_t session_key[HAT_OWNER_KEY_LEN]);
