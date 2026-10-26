// Owner key persistence and challenge verification. Shares the BT library's
// FTL application area with hat_wifi_store.c (offset 0, 116 bytes).

#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "ftl_app.h"
#include "hat_crypto.h"
#include "hat_owner.h"
#include "hat_secure.h"

#define HAT_OWNER_STORE_OFFSET 128
#define HAT_OWNER_STORE_MAGIC 0x4841544Fu // "HATO"
#define HAT_OWNER_STORE_VERSION 1u

typedef struct {
	uint32_t magic;
	uint32_t version;
	uint8_t key[HAT_OWNER_KEY_LEN];
	uint32_t checksum;
} hat_owner_record_t;

_Static_assert(sizeof(hat_owner_record_t) % 4 == 0, "FTL requires 4-byte multiples");

// Read by BLE callbacks, written by claim/reset; guarded by critical sections.
static uint8_t hat_owner_key[HAT_OWNER_KEY_LEN];
static bool hat_owner_present;

static uint32_t hat_owner_checksum(const uint8_t key[HAT_OWNER_KEY_LEN])
{
	uint32_t hash = 2166136261u;
	for (size_t i = 0; i < HAT_OWNER_KEY_LEN; i++) hash = (hash ^ key[i]) * 16777619u;
	return hash;
}

void hat_owner_load(void)
{
	hat_owner_record_t record;
	bool valid = ftl_load(&record, HAT_OWNER_STORE_OFFSET, sizeof(record)) == 0 &&
				 record.magic == HAT_OWNER_STORE_MAGIC && record.version == HAT_OWNER_STORE_VERSION &&
				 record.checksum == hat_owner_checksum(record.key);
	taskENTER_CRITICAL();
	hat_owner_present = valid;
	if (valid) memcpy(hat_owner_key, record.key, sizeof(hat_owner_key));
	taskEXIT_CRITICAL();
	memset(&record, 0, sizeof(record));
}

bool hat_owner_exists(void)
{
	taskENTER_CRITICAL();
	bool present = hat_owner_present;
	taskEXIT_CRITICAL();
	return present;
}

bool hat_owner_save(const uint8_t key[HAT_OWNER_KEY_LEN])
{
	hat_owner_record_t record = { .magic = HAT_OWNER_STORE_MAGIC, .version = HAT_OWNER_STORE_VERSION };
	memcpy(record.key, key, sizeof(record.key));
	record.checksum = hat_owner_checksum(record.key);
	bool saved = ftl_save(&record, HAT_OWNER_STORE_OFFSET, sizeof(record)) == 0;
	memset(&record, 0, sizeof(record));
	if (!saved) return false;

	taskENTER_CRITICAL();
	memcpy(hat_owner_key, key, sizeof(hat_owner_key));
	hat_owner_present = true;
	taskEXIT_CRITICAL();
	return true;
}

bool hat_owner_session_key(const uint8_t nonce[HAT_AUTH_NONCE_LEN], uint8_t session_key[HAT_OWNER_KEY_LEN])
{
	uint8_t key[HAT_OWNER_KEY_LEN];
	taskENTER_CRITICAL();
	bool present = hat_owner_present;
	memcpy(key, hat_owner_key, sizeof(key));
	taskEXIT_CRITICAL();
	bool ok = present && hat_secure_session_key(key, nonce, HAT_AUTH_NONCE_LEN, session_key);
	memset(key, 0, sizeof(key));
	return ok;
}

bool hat_owner_clear(void)
{
	hat_owner_record_t record;
	memset(&record, 0, sizeof(record));
	taskENTER_CRITICAL();
	hat_owner_present = false;
	memset(hat_owner_key, 0, sizeof(hat_owner_key));
	taskEXIT_CRITICAL();
	return ftl_save(&record, HAT_OWNER_STORE_OFFSET, sizeof(record)) == 0;
}

bool hat_owner_verify(const uint8_t nonce[HAT_AUTH_NONCE_LEN], const uint8_t mac[HAT_AUTH_MAC_LEN])
{
	uint8_t key[HAT_OWNER_KEY_LEN];
	taskENTER_CRITICAL();
	bool present = hat_owner_present;
	memcpy(key, hat_owner_key, sizeof(key));
	taskEXIT_CRITICAL();

	uint8_t expected[HAT_AUTH_MAC_LEN];
	bool computed = present && hat_hmac_sha256(key, sizeof(key), nonce, HAT_AUTH_NONCE_LEN, expected);
	memset(key, 0, sizeof(key));
	if (!computed) return false;
	// Compare every byte regardless of where a mismatch occurs.
	uint8_t diff = 0;
	for (size_t i = 0; i < HAT_AUTH_MAC_LEN; i++) diff |= expected[i] ^ mac[i];
	memset(expected, 0, sizeof(expected));
	return diff == 0;
}
