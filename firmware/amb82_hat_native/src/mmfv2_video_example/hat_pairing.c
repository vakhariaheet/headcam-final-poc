#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "hat_pairing.h"

typedef struct {
	bool open;
	uint32_t opened_at;
	uint32_t generation;
	uint8_t conn_id;
	bool authenticated;
	bool disconnect_requested;
	bool nonce_valid;
	uint8_t nonce[HAT_AUTH_NONCE_LEN];
	uint8_t session_key[HAT_OWNER_KEY_LEN];
	uint32_t unauthenticated_since;
} hat_pairing_state_t;

static hat_pairing_state_t hat_pairing = { .conn_id = HAT_NO_CONNECTION };

// Callers hold the critical section.
static void hat_pairing_set_open(bool open, uint32_t now_ms)
{
	if (hat_pairing.open == open) {
		if (open) hat_pairing.opened_at = now_ms; // reopening restarts the window
		return;
	}
	hat_pairing.open = open;
	hat_pairing.opened_at = now_ms;
	hat_pairing.generation++;
	// The authentication deadline only runs while pairing mode is closed.
	if (!open) hat_pairing.unauthenticated_since = now_ms;
}

void hat_pairing_init(bool has_owner, uint32_t now_ms)
{
	taskENTER_CRITICAL();
	hat_pairing_set_open(!has_owner, now_ms);
	taskEXIT_CRITICAL();
}

void hat_pairing_open(uint32_t now_ms)
{
	taskENTER_CRITICAL();
	hat_pairing_set_open(true, now_ms);
	taskEXIT_CRITICAL();
}

void hat_pairing_close(uint32_t now_ms)
{
	taskENTER_CRITICAL();
	hat_pairing_set_open(false, now_ms);
	taskEXIT_CRITICAL();
}

bool hat_pairing_is_open(void)
{
	taskENTER_CRITICAL();
	bool open = hat_pairing.open;
	taskEXIT_CRITICAL();
	return open;
}

uint32_t hat_pairing_generation(void)
{
	taskENTER_CRITICAL();
	uint32_t generation = hat_pairing.generation;
	taskEXIT_CRITICAL();
	return generation;
}

void hat_session_connected(uint8_t conn_id, uint32_t now_ms)
{
	taskENTER_CRITICAL();
	hat_pairing.conn_id = conn_id;
	hat_pairing.authenticated = false;
	hat_pairing.disconnect_requested = false;
	hat_pairing.nonce_valid = false;
	hat_pairing.unauthenticated_since = now_ms;
	taskEXIT_CRITICAL();
}

void hat_session_disconnected(uint8_t conn_id)
{
	taskENTER_CRITICAL();
	if (hat_pairing.conn_id == conn_id) {
		hat_pairing.conn_id = HAT_NO_CONNECTION;
		hat_pairing.authenticated = false;
		hat_pairing.nonce_valid = false;
		memset(hat_pairing.nonce, 0, sizeof(hat_pairing.nonce));
		memset(hat_pairing.session_key, 0, sizeof(hat_pairing.session_key));
	}
	taskEXIT_CRITICAL();
}

bool hat_session_authenticated(uint8_t conn_id)
{
	taskENTER_CRITICAL();
	bool authenticated = conn_id != HAT_NO_CONNECTION && hat_pairing.conn_id == conn_id && hat_pairing.authenticated;
	taskEXIT_CRITICAL();
	return authenticated;
}

bool hat_session_set_nonce(uint8_t conn_id, const uint8_t nonce[HAT_AUTH_NONCE_LEN])
{
	taskENTER_CRITICAL();
	bool active = conn_id != HAT_NO_CONNECTION && hat_pairing.conn_id == conn_id;
	if (active) {
		memcpy(hat_pairing.nonce, nonce, HAT_AUTH_NONCE_LEN);
		hat_pairing.nonce_valid = true;
	}
	taskEXIT_CRITICAL();
	return active;
}

bool hat_session_take_nonce(uint8_t conn_id, uint8_t nonce_out[HAT_AUTH_NONCE_LEN])
{
	taskENTER_CRITICAL();
	bool valid = conn_id != HAT_NO_CONNECTION && hat_pairing.conn_id == conn_id && hat_pairing.nonce_valid;
	if (valid) memcpy(nonce_out, hat_pairing.nonce, HAT_AUTH_NONCE_LEN);
	hat_pairing.nonce_valid = false;
	memset(hat_pairing.nonce, 0, sizeof(hat_pairing.nonce));
	taskEXIT_CRITICAL();
	return valid;
}

void hat_session_authenticate(uint8_t conn_id, const uint8_t session_key[HAT_OWNER_KEY_LEN])
{
	taskENTER_CRITICAL();
	if (conn_id != HAT_NO_CONNECTION && hat_pairing.conn_id == conn_id) {
		hat_pairing.authenticated = true;
		memcpy(hat_pairing.session_key, session_key, HAT_OWNER_KEY_LEN);
	}
	taskEXIT_CRITICAL();
}

bool hat_session_key(uint8_t conn_id, uint8_t session_key[HAT_OWNER_KEY_LEN])
{
	taskENTER_CRITICAL();
	bool authenticated = conn_id != HAT_NO_CONNECTION && hat_pairing.conn_id == conn_id && hat_pairing.authenticated;
	if (authenticated) memcpy(session_key, hat_pairing.session_key, HAT_OWNER_KEY_LEN);
	taskEXIT_CRITICAL();
	return authenticated;
}

void hat_session_claimed(uint32_t now_ms)
{
	taskENTER_CRITICAL();
	hat_pairing_set_open(false, now_ms);
	taskEXIT_CRITICAL();
}

uint8_t hat_pairing_tick(uint32_t now_ms)
{
	uint8_t disconnect = HAT_NO_CONNECTION;
	taskENTER_CRITICAL();
	if (hat_pairing.open && (uint32_t)(now_ms - hat_pairing.opened_at) >= HAT_PAIRING_WINDOW_MS) {
		hat_pairing_set_open(false, now_ms);
	}
	if (!hat_pairing.open && hat_pairing.conn_id != HAT_NO_CONNECTION && !hat_pairing.authenticated &&
		!hat_pairing.disconnect_requested &&
		(uint32_t)(now_ms - hat_pairing.unauthenticated_since) >= HAT_AUTH_TIMEOUT_MS) {
		hat_pairing.disconnect_requested = true;
		disconnect = hat_pairing.conn_id;
	}
	taskEXIT_CRITICAL();
	return disconnect;
}
