// Custom FFE0/FFE1/FFE2 GATT peripheral service — attribute table +
// SET_STA command parsing. Modeled on the SDK's own vendor-UUID pattern in
// component/bluetooth/rtk_stack/src/ble/profile/server/simple_ble_service.c
// (custom 16-bit UUIDs work directly, no 128-bit UUID needed), but this
// table is purpose-built for our own three attributes rather than that
// file's generic V1-V4 read/write/notify/indicate demo set.
//
// START_STREAM/STOP_STREAM use the same FFE1 write handler. Stream I/O
// is owned by the publisher task, never by a BLE callback.

#include <string.h>
#include <stdio.h>

#include "gap.h"
#include "gatt.h"
#include "profile_server.h"
#include "cJSON.h"

#include "ble_provisioning_service.h"
#include "ble_provisioning_task.h"
#include "module_hat_rtmp.h"
#include "hat_wifi_store.h"
#include "hat_camera_guard.h"
#include "hat_crypto.h"
#include "hat_owner.h"
#include "hat_pairing.h"
#include "hat_ota.h"
#include "hat_secure.h"
#include "hat_version.h"
#include "FreeRTOS.h"
#include "task.h"

#define BLE_PROVISIONING_CMD_VALUE_INDEX     2 // FFE1 characteristic value attribute
#define BLE_PROVISIONING_STATUS_VALUE_INDEX  4 // FFE2 characteristic value attribute
#define BLE_PROVISIONING_STATUS_CCCD_INDEX   5

#define BLE_PROVISIONING_CMD_MAX_LEN    512 // real signed-in session JWTs run ~370 bytes

// ATT application error 0x81 (APP_RESULT_APP_ERR is 0x80): the command needs
// an authenticated owner link. The SDK defines no authorization result.
#define BLE_PROVISIONING_RESULT_NOT_AUTHENTICATED ((T_APP_RESULT)(ATT_ERR | (ATT_ERR_MIN_APPLIC_CODE + 1)))
#define BLE_PROVISIONING_STATUS_MAX_LEN 256

T_SERVER_ID ble_provisioning_service_id;
static P_FUN_SERVER_GENERAL_CB ble_provisioning_app_cb;

// Cache of the last status JSON — a read on FFE2 returns whatever the most
// recent SET_STA attempt (or boot-time default) produced, not just what was
// last notified to a still-connected client.
static char ble_provisioning_status[BLE_PROVISIONING_STATUS_MAX_LEN] = "{\"status\":\"idle\"}";

// FFE2 subscriber. Written by the BT task; read by worker/telemetry tasks.
// Byte-sized fields, and a stale read only costs one rejected notification.
static volatile uint8_t ble_provisioning_notify_conn_id = BLE_PROVISIONING_NO_CONN;
static volatile bool ble_provisioning_notify_enabled;

static const T_ATTRIB_APPL ble_provisioning_attr_tbl[] = {
	// Primary service: FFE0
	{
		(ATTRIB_FLAG_VALUE_INCL | ATTRIB_FLAG_LE),
		{
			LO_WORD(GATT_UUID_PRIMARY_SERVICE), HI_WORD(GATT_UUID_PRIMARY_SERVICE),
			LO_WORD(GATT_UUID_HAT_PROVISIONING_SERVICE), HI_WORD(GATT_UUID_HAT_PROVISIONING_SERVICE)
		},
		UUID_16BIT_SIZE, NULL, GATT_PERM_READ
	},

	// FFE1 (write) — characteristic declaration
	{
		ATTRIB_FLAG_VALUE_INCL,
		{
			LO_WORD(GATT_UUID_CHARACTERISTIC), HI_WORD(GATT_UUID_CHARACTERISTIC),
			GATT_CHAR_PROP_WRITE
		},
		1, NULL, GATT_PERM_READ
	},
	// FFE1 (write) — value
	{
		ATTRIB_FLAG_VALUE_APPL,
		{ LO_WORD(GATT_UUID_HAT_PROVISIONING_CMD), HI_WORD(GATT_UUID_HAT_PROVISIONING_CMD) },
		0, NULL,
		GATT_PERM_WRITE
	},

	// FFE2 (read + notify) — characteristic declaration
	{
		ATTRIB_FLAG_VALUE_INCL,
		{
			LO_WORD(GATT_UUID_CHARACTERISTIC), HI_WORD(GATT_UUID_CHARACTERISTIC),
			(GATT_CHAR_PROP_READ | GATT_CHAR_PROP_NOTIFY)
		},
		1, NULL, GATT_PERM_READ
	},
	// FFE2 (read + notify) — value
	{
		ATTRIB_FLAG_VALUE_APPL,
		{ LO_WORD(GATT_UUID_HAT_PROVISIONING_STATUS), HI_WORD(GATT_UUID_HAT_PROVISIONING_STATUS) },
		0, NULL,
		GATT_PERM_READ
	},
	// FFE2 — client characteristic config descriptor (needed for notify)
	{
		ATTRIB_FLAG_VALUE_INCL | ATTRIB_FLAG_CCCD_APPL,
		{
			LO_WORD(GATT_UUID_CHAR_CLIENT_CONFIG), HI_WORD(GATT_UUID_CHAR_CLIENT_CONFIG),
			LO_WORD(GATT_CLIENT_CHAR_CONFIG_DEFAULT), HI_WORD(GATT_CLIENT_CHAR_CONFIG_DEFAULT)
		},
		2, NULL,
		(GATT_PERM_READ | GATT_PERM_WRITE)
	},
};

static T_APP_RESULT ble_provisioning_attr_read_cb(uint8_t conn_id, T_SERVER_ID service_id,
		uint16_t attrib_index, uint16_t offset, uint16_t *p_length, uint8_t **pp_value)
{
	(void)service_id;
	(void)offset;
	static char locked[] = "{\"status\":\"locked\"}";

	if (attrib_index == BLE_PROVISIONING_STATUS_VALUE_INDEX) {
		// The cached status can include the hat's IP; only the owner sees it.
		char *value = hat_session_authenticated(conn_id) ? ble_provisioning_status : locked;
		*p_length = strlen(value);
		*pp_value = (uint8_t *)value;
		return APP_RESULT_SUCCESS;
	}
	return APP_RESULT_ATTR_NOT_FOUND;
}

// Replies to the link that asked, whether or not it has authenticated yet.
static void ble_provisioning_reply(uint8_t conn_id, const char *json)
{
	if (!ble_provisioning_notify_enabled || conn_id != ble_provisioning_notify_conn_id) {
		printf("\r\n[ble_provisioning] reply dropped: FFE2 notifications not enabled\r\n");
		return;
	}
	server_send_data(conn_id, ble_provisioning_service_id, BLE_PROVISIONING_STATUS_VALUE_INDEX,
					 (uint8_t *)json, strlen(json), GATT_PDU_TYPE_NOTIFICATION);
}

static void ble_provisioning_hex_encode(const uint8_t *bytes, size_t len, char *out)
{
	static const char digits[] = "0123456789abcdef";
	for (size_t i = 0; i < len; i++) {
		out[2 * i] = digits[bytes[i] >> 4];
		out[2 * i + 1] = digits[bytes[i] & 0x0F];
	}
	out[2 * len] = '\0';
}

static int ble_provisioning_hex_digit(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

static bool ble_provisioning_hex_decode(const char *hex, uint8_t *out, size_t len)
{
	if (!hex || strlen(hex) != 2 * len) return false;
	for (size_t i = 0; i < len; i++) {
		int high = ble_provisioning_hex_digit(hex[2 * i]);
		int low = ble_provisioning_hex_digit(hex[2 * i + 1]);
		if (high < 0 || low < 0) return false;
		out[i] = (uint8_t)(high << 4 | low);
	}
	return true;
}

static uint32_t ble_provisioning_now_ms(void)
{
	return (uint32_t)xTaskGetTickCount() * portTICK_PERIOD_MS;
}

static void ble_provisioning_reply_error(uint8_t conn_id, const char *event, const char *reason)
{
	char json[96];
	snprintf(json, sizeof(json), "{\"event\":\"%s\",\"status\":\"error\",\"reason\":\"%s\"}", event, reason);
	ble_provisioning_reply(conn_id, json);
}

// {"cmd":"CLAIM","pub":"<base64 P-256 public key>"} in pairing mode: ECDH
// with a fresh hat key pair; both sides derive the owner key (hat_secure.h),
// so it never crosses the air. Replaces any previous owner and closes pairing
// mode. The link must then authenticate like a returning owner.
static void ble_provisioning_handle_claim(uint8_t conn_id, cJSON *root)
{
	if (!hat_pairing_is_open()) {
		ble_provisioning_reply_error(conn_id, "claim", "pairing_closed");
		return;
	}
	cJSON *pub_item = cJSON_GetObjectItem(root, "pub");
	uint8_t key[HAT_OWNER_KEY_LEN];
	char hat_public[4 * ((HAT_P256_PUBLIC_KEY_LEN + 2) / 3) + 1];
	if (!cJSON_IsString(pub_item) ||
		!hat_secure_claim(pub_item->valuestring, hat_public, sizeof(hat_public), key)) {
		ble_provisioning_reply_error(conn_id, "claim", "bad_request");
		return;
	}
	bool saved = hat_owner_save(key);
	memset(key, 0, sizeof(key));
	if (!saved) {
		ble_provisioning_reply_error(conn_id, "claim", "key_store_failed");
		return;
	}
	hat_session_claimed(ble_provisioning_now_ms());
	printf("\r\n[ble_provisioning] claimed by new owner; pairing mode closed\r\n");

	char json[64 + sizeof(hat_public)];
	snprintf(json, sizeof(json), "{\"event\":\"claim\",\"status\":\"ok\",\"pub\":\"%s\"}", hat_public);
	ble_provisioning_reply(conn_id, json);
}

// {"cmd":"AUTH_START"} issues a single-use challenge for this link.
static void ble_provisioning_handle_auth_start(uint8_t conn_id)
{
	uint8_t nonce[HAT_AUTH_NONCE_LEN];
	if (!hat_owner_exists()) {
		ble_provisioning_reply(conn_id, "{\"event\":\"auth\",\"status\":\"error\",\"reason\":\"no_owner\"}");
		return;
	}
	if (!hat_random_bytes(nonce, sizeof(nonce)) || !hat_session_set_nonce(conn_id, nonce)) {
		ble_provisioning_reply(conn_id, "{\"event\":\"auth\",\"status\":\"error\",\"reason\":\"challenge_failed\"}");
		return;
	}
	char nonce_hex[2 * HAT_AUTH_NONCE_LEN + 1];
	char json[64 + 2 * HAT_AUTH_NONCE_LEN];
	ble_provisioning_hex_encode(nonce, sizeof(nonce), nonce_hex);
	snprintf(json, sizeof(json), "{\"event\":\"auth\",\"nonce\":\"%s\"}", nonce_hex);
	ble_provisioning_reply(conn_id, json);
}

// {"cmd":"AUTH","mac":"<hex HMAC-SHA256(owner key, nonce)>"}
static void ble_provisioning_handle_auth(uint8_t conn_id, cJSON *root)
{
	cJSON *mac_item = cJSON_GetObjectItem(root, "mac");
	uint8_t mac[HAT_AUTH_MAC_LEN];
	uint8_t nonce[HAT_AUTH_NONCE_LEN];
	// Taking the nonce first makes every attempt, valid or not, consume it.
	bool challenged = hat_session_take_nonce(conn_id, nonce);
	const char *reason = NULL;
	if (!challenged) {
		reason = "no_challenge";
	} else if (!cJSON_IsString(mac_item) || !ble_provisioning_hex_decode(mac_item->valuestring, mac, sizeof(mac))) {
		reason = "bad_request";
	} else if (!hat_owner_verify(nonce, mac)) {
		reason = "not_owner";
	}
	uint8_t session_key[HAT_OWNER_KEY_LEN];
	if (!reason && !hat_owner_session_key(nonce, session_key)) reason = "challenge_failed";
	if (reason) {
		ble_provisioning_reply_error(conn_id, "auth", reason);
		return;
	}
	hat_session_authenticate(conn_id, session_key);
	memset(session_key, 0, sizeof(session_key));
	ble_provisioning_reply(conn_id, "{\"event\":\"auth\",\"status\":\"ok\"}");
}

// Decrypts {"cmd":X,"sealed":"<base64>"} into its JSON parameters with this
// link's session key; the command name is bound as associated data, so a
// sealed SET_STA cannot be replayed as another command. NULL on failure.
static cJSON *ble_provisioning_open_params(uint8_t conn_id, const char *cmd, cJSON *root)
{
	cJSON *sealed = cJSON_GetObjectItem(root, "sealed");
	uint8_t session_key[HAT_OWNER_KEY_LEN];
	char params[BLE_PROVISIONING_CMD_MAX_LEN];
	if (!cJSON_IsString(sealed) || !hat_session_key(conn_id, session_key)) return NULL;
	bool opened = hat_secure_open(session_key, cmd, sealed->valuestring, params, sizeof(params));
	memset(session_key, 0, sizeof(session_key));
	cJSON *parsed = opened ? cJSON_Parse(params) : NULL;
	memset(params, 0, sizeof(params));
	if (!parsed) printf("\r\n[ble_provisioning] %s: sealed parameters rejected\r\n", cmd);
	return parsed;
}

// Handles SET_STA's sealed {"ssid":...,"pass":...} parameters: hands off to
// ble_provisioning_task's deferred queue (never connects to Wi-Fi from this
// callback directly — see ble_provisioning_task.c's header comment for why,
// same root cause as the Arduino firmware's documented stack-overflow bug
// this replaces). Plaintext credentials are refused.
static T_APP_RESULT ble_provisioning_handle_set_sta(uint8_t conn_id, cJSON *root)
{
	cJSON *params = ble_provisioning_open_params(conn_id, "SET_STA", root);
	if (!params) return APP_RESULT_APP_ERR;
	cJSON *ssid_item = cJSON_GetObjectItem(params, "ssid");
	cJSON *pass_item = cJSON_GetObjectItem(params, "pass");
	T_APP_RESULT result = APP_RESULT_APP_ERR;
	if (cJSON_IsString(ssid_item) && cJSON_IsString(pass_item)) {
		cJSON *session_token_item = cJSON_GetObjectItem(params, "session_token");
		const char *session_token = cJSON_IsString(session_token_item) ? session_token_item->valuestring : NULL;
		if (ble_provisioning_request_connect(conn_id, ssid_item->valuestring, pass_item->valuestring, session_token)) {
			result = APP_RESULT_SUCCESS;
		}
	} else {
		printf("\r\n[ble_provisioning] SET_STA missing ssid/pass\r\n");
	}
	// Scrub the passphrase from the parsed tree before freeing it.
	if (cJSON_IsString(pass_item)) memset(pass_item->valuestring, 0, strlen(pass_item->valuestring));
	cJSON_Delete(params);
	return result;
}

// {"cmd":"INFO"}: identity for account linking, the firmware version for
// updates, and camera health so the app can explain restarts.
static void ble_provisioning_handle_info(uint8_t conn_id)
{
	uint8_t bt_addr[6];
	char id[13];
	gap_get_param(GAP_PARAM_BD_ADDR, bt_addr);
	// Most significant byte first, as the address is usually written.
	snprintf(id, sizeof(id), "%02X%02X%02X%02X%02X%02X",
			 bt_addr[5], bt_addr[4], bt_addr[3], bt_addr[2], bt_addr[1], bt_addr[0]);
	uint8_t restarts = hat_camera_guard_restarts();
	const char *camera = hat_camera_guard_stopped() ? "failed" : restarts > 0 ? "recovered" : "ok";
	char json[192];
	snprintf(json, sizeof(json),
			 "{\"event\":\"info\",\"id\":\"%s\",\"model\":\"%s\",\"fw\":\"%s\","
			 "\"camera\":\"%s\",\"camera_restarts\":%u,\"camera_max\":%u}",
			 id, HAT_HARDWARE_MODEL, HAT_FIRMWARE_VERSION, camera, (unsigned)restarts,
			 (unsigned)HAT_CAMERA_MAX_RESTARTS);
	ble_provisioning_reply(conn_id, json);
}

// Release names go into a JSON reply and an HTTP header: keep them plain.
static bool ble_provisioning_valid_version(const char *version)
{
	size_t len = strlen(version);
	if (len == 0 || len > 20) return false;
	for (size_t i = 0; i < len; i++) {
		char c = version[i];
		bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				  c == '.' || c == '-' || c == '+';
		if (!ok) return false;
	}
	return true;
}

// Sealed {"url":"http://...","size":N,"sha256":"<hex>","version":"x.y.z"}.
// The hash arrives under the session key, so the image itself can travel
// over plain HTTP. Answers on FFE2 with started or an error.
static void ble_provisioning_handle_update_fw(uint8_t conn_id, cJSON *root)
{
	cJSON *params = ble_provisioning_open_params(conn_id, "UPDATE_FW", root);
	if (!params) {
		ble_provisioning_reply_error(conn_id, "ota", "bad_request");
		return;
	}
	cJSON *url = cJSON_GetObjectItem(params, "url");
	cJSON *size = cJSON_GetObjectItem(params, "size");
	cJSON *hash = cJSON_GetObjectItem(params, "sha256");
	cJSON *version = cJSON_GetObjectItem(params, "version");
	uint8_t sha256[HAT_OTA_SHA256_LEN];
	const char *reason = NULL;
	if (!cJSON_IsString(url) || !cJSON_IsNumber(size) || size->valuedouble < 0 || size->valuedouble > UINT32_MAX ||
		!cJSON_IsString(hash) || !ble_provisioning_hex_decode(hash->valuestring, sha256, sizeof(sha256)) ||
		!cJSON_IsString(version) || !ble_provisioning_valid_version(version->valuestring)) {
		reason = "bad_request";
	} else {
		reason = hat_ota_start(url->valuestring, (uint32_t)size->valuedouble, sha256, version->valuestring);
	}
	if (reason) {
		ble_provisioning_reply_error(conn_id, "ota", reason);
	} else {
		printf("\r\n[ble_provisioning] firmware update to %s started\r\n", version->valuestring);
		ble_provisioning_reply(conn_id, "{\"event\":\"ota\",\"status\":\"started\"}");
	}
	cJSON_Delete(params);
}

// START_STREAM with no URL uses the firmware default. A URL can carry a
// stream key, so it is only accepted sealed.
static T_APP_RESULT ble_provisioning_handle_start_stream(uint8_t conn_id, cJSON *root)
{
	if (hat_ota_in_progress()) {
		printf("\r\n[ble_provisioning] START_STREAM refused: firmware update in progress\r\n");
		return APP_RESULT_APP_ERR;
	}
	if (cJSON_GetObjectItem(root, "url")) {
		printf("\r\n[ble_provisioning] START_STREAM: plaintext url refused; seal it\r\n");
		return APP_RESULT_APP_ERR;
	}
	if (!cJSON_GetObjectItem(root, "sealed")) {
		return hat_stream_start(NULL, conn_id) ? APP_RESULT_SUCCESS : APP_RESULT_APP_ERR;
	}
	cJSON *params = ble_provisioning_open_params(conn_id, "START_STREAM", root);
	if (!params) return APP_RESULT_APP_ERR;
	cJSON *url = cJSON_GetObjectItem(params, "url");
	T_APP_RESULT result = APP_RESULT_APP_ERR;
	if (!url || cJSON_IsString(url)) {
		result = hat_stream_start(url ? url->valuestring : NULL, conn_id) ? APP_RESULT_SUCCESS : APP_RESULT_APP_ERR;
	}
	if (cJSON_IsString(url)) memset(url->valuestring, 0, strlen(url->valuestring));
	cJSON_Delete(params);
	return result;
}

static T_APP_RESULT ble_provisioning_attr_write_cb(uint8_t conn_id, T_SERVER_ID service_id,
		uint16_t attrib_index, T_WRITE_TYPE write_type, uint16_t length, uint8_t *p_value,
		P_FUN_WRITE_IND_POST_PROC *p_write_ind_post_proc)
{
	(void)service_id;
	(void)write_type;
	(void)p_write_ind_post_proc;

	if (attrib_index != BLE_PROVISIONING_CMD_VALUE_INDEX) {
		return APP_RESULT_ATTR_NOT_FOUND;
	}
	if (length == 0 || length >= BLE_PROVISIONING_CMD_MAX_LEN) {
		return APP_RESULT_INVALID_VALUE_SIZE;
	}

	char buf[BLE_PROVISIONING_CMD_MAX_LEN];
	memcpy(buf, p_value, length);
	buf[length] = '\0';

	cJSON *root = cJSON_Parse(buf);
	if (!root) {
		printf("\r\n[ble_provisioning] invalid JSON on FFE1\r\n");
		return APP_RESULT_APP_ERR;
	}

	T_APP_RESULT result = APP_RESULT_APP_ERR;
	cJSON *cmd_item = cJSON_GetObjectItem(root, "cmd");
	const char *cmd = cJSON_IsString(cmd_item) ? cmd_item->valuestring : NULL;
	// Ownership commands answer on FFE2; everything else needs the owner.
	if (cmd && strcmp(cmd, "CLAIM") == 0) {
		ble_provisioning_handle_claim(conn_id, root);
		result = APP_RESULT_SUCCESS;
	} else if (cmd && strcmp(cmd, "AUTH_START") == 0) {
		ble_provisioning_handle_auth_start(conn_id);
		result = APP_RESULT_SUCCESS;
	} else if (cmd && strcmp(cmd, "AUTH") == 0) {
		ble_provisioning_handle_auth(conn_id, root);
		result = APP_RESULT_SUCCESS;
	} else if (cmd && !hat_session_authenticated(conn_id)) {
		printf("\r\n[ble_provisioning] %s rejected: link not authenticated\r\n", cmd);
		result = BLE_PROVISIONING_RESULT_NOT_AUTHENTICATED;
	} else if (cmd) {
		if (strcmp(cmd_item->valuestring, "SET_STA") == 0) {
			result = ble_provisioning_handle_set_sta(conn_id, root);
		} else if (strcmp(cmd_item->valuestring, "START_STREAM") == 0) {
			result = ble_provisioning_handle_start_stream(conn_id, root);
		} else if (strcmp(cmd_item->valuestring, "STOP_STREAM") == 0) {
			hat_stream_stop(conn_id);
			result = APP_RESULT_SUCCESS;
		} else if (strcmp(cmd_item->valuestring, "INFO") == 0) {
			ble_provisioning_handle_info(conn_id);
			result = APP_RESULT_SUCCESS;
		} else if (strcmp(cmd_item->valuestring, "UPDATE_FW") == 0) {
			ble_provisioning_handle_update_fw(conn_id, root);
			result = APP_RESULT_SUCCESS;
		} else if (strcmp(cmd_item->valuestring, "CLEAR_STA") == 0) {
			// Forget the saved network; the current association stays up until reboot.
			result = hat_wifi_store_clear() ? APP_RESULT_SUCCESS : APP_RESULT_APP_ERR;
		} else {
			printf("\r\n[ble_provisioning] unknown cmd: %s\r\n", cmd_item->valuestring);
		}
	}

	cJSON_Delete(root);
	return result;
}

static void ble_provisioning_cccd_update_cb(uint8_t conn_id, T_SERVER_ID service_id,
		uint16_t attrib_index, uint16_t ccc_bits)
{
	(void)service_id;
	if (attrib_index == BLE_PROVISIONING_STATUS_CCCD_INDEX) {
		bool enabled = (ccc_bits & GATT_CLIENT_CHAR_CONFIG_NOTIFY) != 0;
		ble_provisioning_notify_conn_id = conn_id;
		ble_provisioning_notify_enabled = enabled;
		printf("\r\n[ble_provisioning] FFE2 notify %s\r\n", enabled ? "enabled" : "disabled");
	}
}

static const T_FUN_GATT_SERVICE_CBS ble_provisioning_service_cbs = {
	ble_provisioning_attr_read_cb,
	ble_provisioning_attr_write_cb,
	ble_provisioning_cccd_update_cb
};

T_SERVER_ID ble_provisioning_service_add(void *p_func)
{
	if (!server_add_service(&ble_provisioning_service_id, (uint8_t *)ble_provisioning_attr_tbl,
							 sizeof(ble_provisioning_attr_tbl), ble_provisioning_service_cbs)) {
		printf("\r\n[ble_provisioning] server_add_service failed\r\n");
	}
	ble_provisioning_app_cb = (P_FUN_SERVER_GENERAL_CB)p_func;
	(void)ble_provisioning_app_cb;
	return ble_provisioning_service_id;
}

bool ble_provisioning_service_notify_status(uint8_t conn_id, const char *json, uint16_t len)
{
	uint16_t copy_len = (len < sizeof(ble_provisioning_status) - 1) ? len : (sizeof(ble_provisioning_status) - 1);
	memcpy(ble_provisioning_status, json, copy_len);
	ble_provisioning_status[copy_len] = '\0';

	if (!ble_provisioning_notify_enabled || conn_id != ble_provisioning_notify_conn_id ||
		!hat_session_authenticated(conn_id)) {
		return false;
	}
	return server_send_data(conn_id, ble_provisioning_service_id, BLE_PROVISIONING_STATUS_VALUE_INDEX,
							 (uint8_t *)ble_provisioning_status, copy_len, GATT_PDU_TYPE_ANY);
}

bool ble_provisioning_service_notify_event(const char *json, uint16_t len)
{
	uint8_t conn_id = ble_provisioning_notify_conn_id;
	if (!ble_provisioning_notify_enabled || conn_id == BLE_PROVISIONING_NO_CONN ||
		!hat_session_authenticated(conn_id)) {
		return false;
	}
	return server_send_data(conn_id, ble_provisioning_service_id, BLE_PROVISIONING_STATUS_VALUE_INDEX,
							 (uint8_t *)json, len, GATT_PDU_TYPE_NOTIFICATION);
}

void ble_provisioning_service_on_disconnect(uint8_t conn_id)
{
	if (conn_id != ble_provisioning_notify_conn_id) return;
	ble_provisioning_notify_enabled = false;
	ble_provisioning_notify_conn_id = BLE_PROVISIONING_NO_CONN;
}
