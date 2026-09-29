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

#include "gatt.h"
#include "profile_server.h"
#include "cJSON.h"

#include "ble_provisioning_service.h"
#include "ble_provisioning_task.h"
#include "module_hat_rtmp.h"

#define BLE_PROVISIONING_CMD_VALUE_INDEX     2 // FFE1 characteristic value attribute
#define BLE_PROVISIONING_STATUS_VALUE_INDEX  4 // FFE2 characteristic value attribute
#define BLE_PROVISIONING_STATUS_CCCD_INDEX   5

#define BLE_PROVISIONING_CMD_MAX_LEN    512 // real signed-in session JWTs run ~370 bytes
#define BLE_PROVISIONING_STATUS_MAX_LEN 256

T_SERVER_ID ble_provisioning_service_id;
static P_FUN_SERVER_GENERAL_CB ble_provisioning_app_cb;

// Cache of the last status JSON — a read on FFE2 returns whatever the most
// recent SET_STA attempt (or boot-time default) produced, not just what was
// last notified to a still-connected client.
static char ble_provisioning_status[BLE_PROVISIONING_STATUS_MAX_LEN] = "{\"status\":\"idle\"}";

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
	(void)conn_id;
	(void)service_id;
	(void)offset;

	if (attrib_index == BLE_PROVISIONING_STATUS_VALUE_INDEX) {
		*p_length = strlen(ble_provisioning_status);
		*pp_value = (uint8_t *)ble_provisioning_status;
		return APP_RESULT_SUCCESS;
	}
	return APP_RESULT_ATTR_NOT_FOUND;
}

// Handles a parsed {"cmd":"SET_STA",...} write: pulls ssid/pass, hands off
// to ble_provisioning_task's deferred queue (never connects to Wi-Fi from
// this callback directly — see ble_provisioning_task.c's header comment for
// why, same root cause as the Arduino firmware's documented stack-overflow
// bug this replaces).
static T_APP_RESULT ble_provisioning_handle_set_sta(uint8_t conn_id, cJSON *root)
{
	cJSON *ssid_item = cJSON_GetObjectItem(root, "ssid");
	cJSON *pass_item = cJSON_GetObjectItem(root, "pass");
	if (!cJSON_IsString(ssid_item) || !cJSON_IsString(pass_item)) {
		printf("\r\n[ble_provisioning] SET_STA missing ssid/pass\r\n");
		return APP_RESULT_APP_ERR;
	}

	cJSON *session_token_item = cJSON_GetObjectItem(root, "session_token");
	const char *session_token = cJSON_IsString(session_token_item) ? session_token_item->valuestring : NULL;

	return ble_provisioning_request_connect(conn_id, ssid_item->valuestring, pass_item->valuestring, session_token)
		? APP_RESULT_SUCCESS : APP_RESULT_APP_ERR;
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
	if (cJSON_IsString(cmd_item)) {
		if (strcmp(cmd_item->valuestring, "SET_STA") == 0) {
			result = ble_provisioning_handle_set_sta(conn_id, root);
		} else if (strcmp(cmd_item->valuestring, "START_STREAM") == 0) {
			cJSON *url = cJSON_GetObjectItem(root, "url");
			if (!url || cJSON_IsString(url)) {
				result = hat_stream_start(url ? url->valuestring : NULL, conn_id)
					? APP_RESULT_SUCCESS : APP_RESULT_APP_ERR;
			}
		} else if (strcmp(cmd_item->valuestring, "STOP_STREAM") == 0) {
			hat_stream_stop(conn_id);
			result = APP_RESULT_SUCCESS;
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
	(void)conn_id;
	(void)service_id;
	if (attrib_index == BLE_PROVISIONING_STATUS_CCCD_INDEX) {
		printf("\r\n[ble_provisioning] FFE2 notify %s\r\n",
			   (ccc_bits & GATT_CLIENT_CHAR_CONFIG_NOTIFY) ? "enabled" : "disabled");
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

	return server_send_data(conn_id, ble_provisioning_service_id, BLE_PROVISIONING_STATUS_VALUE_INDEX,
							 (uint8_t *)ble_provisioning_status, copy_len, GATT_PDU_TYPE_ANY);
}
