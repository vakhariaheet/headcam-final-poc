// Wi-Fi credential persistence over the BT library's ftl_save()/ftl_load().
// Those add the stack's own start offset, so application offset 0 cannot
// overlap bond storage. FTL offsets and sizes must be multiples of four.

#include <stdint.h>
#include <string.h>

#include "ftl_app.h"
#include "hat_wifi_store.h"

#define HAT_WIFI_STORE_OFFSET 0
#define HAT_WIFI_STORE_MAGIC 0x48415457u // "HATW"
#define HAT_WIFI_STORE_VERSION 1u

typedef struct {
	uint32_t magic;
	uint32_t version;
	uint32_t checksum;
	char ssid[36];
	char pass[68];
} hat_wifi_record_t;

_Static_assert(sizeof(hat_wifi_record_t) % 4 == 0, "FTL requires 4-byte multiples");
_Static_assert(sizeof(((hat_wifi_record_t *)0)->ssid) >= HAT_WIFI_SSID_MAX_LEN, "ssid fits");
_Static_assert(sizeof(((hat_wifi_record_t *)0)->pass) >= HAT_WIFI_PASS_MAX_LEN, "pass fits");

// FNV-1a over both fields; detects torn or foreign records, not tampering.
static uint32_t hat_wifi_record_checksum(const hat_wifi_record_t *record)
{
	uint32_t hash = 2166136261u;
	const uint8_t *fields[] = { (const uint8_t *)record->ssid, (const uint8_t *)record->pass };
	const size_t sizes[] = { sizeof(record->ssid), sizeof(record->pass) };
	for (int field = 0; field < 2; field++) {
		for (size_t i = 0; i < sizes[field]; i++) {
			hash = (hash ^ fields[field][i]) * 16777619u;
		}
	}
	return hash;
}

static bool hat_wifi_record_read(hat_wifi_record_t *record)
{
	if (ftl_load(record, HAT_WIFI_STORE_OFFSET, sizeof(*record)) != 0) return false;
	if (record->magic != HAT_WIFI_STORE_MAGIC || record->version != HAT_WIFI_STORE_VERSION) return false;
	if (record->checksum != hat_wifi_record_checksum(record)) return false;
	size_t ssid_len = strnlen(record->ssid, sizeof(record->ssid));
	size_t pass_len = strnlen(record->pass, sizeof(record->pass));
	return ssid_len > 0 && ssid_len < HAT_WIFI_SSID_MAX_LEN && pass_len < HAT_WIFI_PASS_MAX_LEN;
}

bool hat_wifi_store_load(hat_wifi_credentials_t *out)
{
	hat_wifi_record_t record;
	if (!hat_wifi_record_read(&record)) return false;
	memset(out, 0, sizeof(*out));
	memcpy(out->ssid, record.ssid, strlen(record.ssid));
	memcpy(out->pass, record.pass, strlen(record.pass));
	return true;
}

bool hat_wifi_store_save(const char *ssid, const char *pass)
{
	size_t ssid_len = strlen(ssid);
	size_t pass_len = strlen(pass);
	if (ssid_len == 0 || ssid_len >= HAT_WIFI_SSID_MAX_LEN || pass_len >= HAT_WIFI_PASS_MAX_LEN) return false;

	hat_wifi_record_t record;
	memset(&record, 0, sizeof(record));
	record.magic = HAT_WIFI_STORE_MAGIC;
	record.version = HAT_WIFI_STORE_VERSION;
	memcpy(record.ssid, ssid, ssid_len);
	memcpy(record.pass, pass, pass_len);
	record.checksum = hat_wifi_record_checksum(&record);

	hat_wifi_record_t existing;
	if (hat_wifi_record_read(&existing) && memcmp(&existing, &record, sizeof(record)) == 0) return true;
	return ftl_save(&record, HAT_WIFI_STORE_OFFSET, sizeof(record)) == 0;
}

bool hat_wifi_store_clear(void)
{
	hat_wifi_record_t record;
	memset(&record, 0, sizeof(record));
	return ftl_save(&record, HAT_WIFI_STORE_OFFSET, sizeof(record)) == 0;
}
