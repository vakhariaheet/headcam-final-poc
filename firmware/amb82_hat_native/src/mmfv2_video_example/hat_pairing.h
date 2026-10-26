#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "hat_owner.h"

// Pairing window and per-connection ownership state. Hardware-independent:
// callers pass a millisecond clock. Safe from the BT task and control task.
//
// Pairing mode opens at boot when no owner exists, or on a button hold, and
// closes after HAT_PAIRING_WINDOW_MS, on a short press, or when a phone
// claims the hat. Only in pairing mode may an unauthenticated connection
// claim ownership. Outside it, a connection that has not authenticated within
// HAT_AUTH_TIMEOUT_MS is disconnected so it cannot block the owner's phone
// (the hat accepts one BLE link at a time).

#define HAT_PAIRING_WINDOW_MS (10u * 60u * 1000u)
#define HAT_AUTH_TIMEOUT_MS (30u * 1000u)
#define HAT_NO_CONNECTION 0xFF

void hat_pairing_init(bool has_owner, uint32_t now_ms);
void hat_pairing_open(uint32_t now_ms);
void hat_pairing_close(uint32_t now_ms);
bool hat_pairing_is_open(void);
// Increments whenever the open state changes; pollers refresh advertising.
uint32_t hat_pairing_generation(void);

void hat_session_connected(uint8_t conn_id, uint32_t now_ms);
void hat_session_disconnected(uint8_t conn_id);
bool hat_session_authenticated(uint8_t conn_id);
// Stores a fresh challenge for conn_id. False if conn_id is not the active link.
bool hat_session_set_nonce(uint8_t conn_id, const uint8_t nonce[HAT_AUTH_NONCE_LEN]);
// Returns and clears the outstanding challenge; each nonce is single-use.
bool hat_session_take_nonce(uint8_t conn_id, uint8_t nonce_out[HAT_AUTH_NONCE_LEN]);
// Marks the link as the owner's and stores its session key for sealed commands.
void hat_session_authenticate(uint8_t conn_id, const uint8_t session_key[HAT_OWNER_KEY_LEN]);
// Copies the session key of an authenticated link.
bool hat_session_key(uint8_t conn_id, uint8_t session_key[HAT_OWNER_KEY_LEN]);
// A successful claim closes pairing mode. The link must still authenticate
// (AUTH_START/AUTH) to get a session key, exactly like a returning owner.
void hat_session_claimed(uint32_t now_ms);

// Expires the pairing window. Returns the connection to disconnect for
// failing to authenticate in time, or HAT_NO_CONNECTION. Reports each link once.
uint8_t hat_pairing_tick(uint32_t now_ms);
