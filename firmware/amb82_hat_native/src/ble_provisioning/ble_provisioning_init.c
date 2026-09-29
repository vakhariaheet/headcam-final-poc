// BLE stack bring-up + GAP glue for the UmpireHat provisioning service.
// Adapted and substantially trimmed from
// component/bluetooth/rtk_stack/example/ble_peripheral/ (ble_app_main.c +
// the subset of peripheral_app.c this app actually needs) — dropped
// entirely: legacy-adv-concurrent, extended advertising, privacy/address
// randomization, OOB pairing, PHY-preference, and the runtime-writable-name
// GATT service, none of which this hat uses. component/bluetooth/rtk_stack/
// example/ble_peripheral/app_task.c (the generic FreeRTOS task/message-pump
// plumbing) is reused unchanged from the SDK — see this project's
// application.cmake edit — since it has no example-specific content to
// adapt.
//
// The mobile BLE flow connects and writes without an OS bonding dialog.
// GAP_PAIRING_MODE_NO_PAIRING preserves that protocol. This does not
// provide BLE link encryption for provisioning credentials.

#include <platform_opts_bt.h>
#if defined(CONFIG_BT_PERIPHERAL) && CONFIG_BT_PERIPHERAL

#include <string.h>
#include <stdio.h>

#include <os_sched.h>
#include <app_msg.h>
#include <trace_app.h>
#include <gap.h>
#include <gap_adv.h>
#include <gap_bond_le.h>
#include <gap_msg.h>
#include <gap_config.h>
#include <profile_server.h>
#include <bte.h>
#include "app_task.h"
#include "app_flags.h"
#include "vendor_cmd.h"
#include "rtk_coex.h"

#include "FreeRTOS.h"
#include "task.h"
#include "wifi_conf.h"

#include "ble_provisioning_init.h"
#include "ble_provisioning_service.h"
#include "ble_provisioning_task.h"

#define DEFAULT_ADVERTISING_INTERVAL_MIN 352 // 220ms
#define DEFAULT_ADVERTISING_INTERVAL_MAX 384 // 240ms

#define HAT_ADV_NAME_PREFIX "UmpireHat_"
#define HAT_ADV_NAME_PREFIX_LEN 10
#define HAT_ADV_NAME_SUFFIX_LEN 4
#define HAT_ADV_NAME_LEN (HAT_ADV_NAME_PREFIX_LEN + HAT_ADV_NAME_SUFFIX_LEN)
#define HAT_ADV_NAME_OFFSET 9 // index of the first name char inside hat_adv_data[]

T_GAP_DEV_STATE gap_dev_state = {0, 0, 0, 0, 0};
static T_GAP_CONN_STATE gap_conn_state = GAP_CONN_STATE_DISCONNECTED;

static const uint8_t scan_rsp_data[] = {
	0x03, GAP_ADTYPE_APPEARANCE, LO_WORD(GAP_GATT_APPEARANCE_UNKNOWN), HI_WORD(GAP_GATT_APPEARANCE_UNKNOWN),
};

// Local name starts as a placeholder; app_handle_dev_state_evt() overwrites
// the last 4 chars with the real BT MAC suffix once the stack is ready and
// the MAC is actually readable (see that function).
static uint8_t hat_adv_data[] = {
	0x02, GAP_ADTYPE_FLAGS, GAP_ADTYPE_FLAGS_LIMITED | GAP_ADTYPE_FLAGS_BREDR_NOT_SUPPORTED,
	0x03, GAP_ADTYPE_16BIT_COMPLETE,
	LO_WORD(GATT_UUID_HAT_PROVISIONING_SERVICE), HI_WORD(GATT_UUID_HAT_PROVISIONING_SERVICE),
	(1 + HAT_ADV_NAME_LEN), GAP_ADTYPE_LOCAL_NAME_COMPLETE,
	'U', 'm', 'p', 'i', 'r', 'e', 'H', 'a', 't', '_', '0', '0', '0', '0',
};

void driver_init(void)
{
}

static void bt_stack_config_init(void)
{
	gap_config_max_le_link_num(APP_MAX_LINKS);
	gap_config_max_le_paired_device(APP_MAX_LINKS);
}

void board_init(void)
{
}

void pwr_mgr_init(void)
{
}

static void task_init(void)
{
	app_task_init();
}

static void app_vendor_callback(uint8_t cb_type, void *p_cb_data)
{
	(void)cb_type;
	(void)p_cb_data;
}

static T_APP_RESULT app_gap_callback(uint8_t cb_type, void *p_cb_data)
{
	(void)cb_type;
	(void)p_cb_data;
	return APP_RESULT_SUCCESS;
}

static T_APP_RESULT app_profile_callback(T_SERVER_ID service_id, void *p_data)
{
	// FFE1/FFE2 read/write/cccd events are fully handled by
	// ble_provisioning_service.c's own T_FUN_GATT_SERVICE_CBS, registered
	// directly with server_add_service() — this generic callback only needs
	// the service-independent lifecycle events.
	if (service_id == SERVICE_PROFILE_GENERAL_ID) {
		T_SERVER_APP_CB_DATA *p_param = (T_SERVER_APP_CB_DATA *)p_data;
		if (p_param->eventId == PROFILE_EVT_SRV_REG_COMPLETE) {
			printf("\r\n[ble_provisioning] service registered: result %d\r\n",
				   p_param->event_data.service_reg_result);
		}
	}
	return APP_RESULT_SUCCESS;
}

static void app_handle_dev_state_evt(T_GAP_DEV_STATE new_state, uint16_t cause)
{
	(void)cause;
	if (gap_dev_state.gap_init_state != new_state.gap_init_state
		&& new_state.gap_init_state == GAP_INIT_STATE_STACK_READY) {
		uint8_t bt_addr[6];
		gap_get_param(GAP_PARAM_BD_ADDR, bt_addr);
		printf("\r\n[ble_provisioning] GAP stack ready, BD addr %02x:%02x:%02x:%02x:%02x:%02x\r\n",
			   bt_addr[5], bt_addr[4], bt_addr[3], bt_addr[2], bt_addr[1], bt_addr[0]);

		char suffix[HAT_ADV_NAME_SUFFIX_LEN + 1];
		snprintf(suffix, sizeof(suffix), "%02X%02X", bt_addr[1], bt_addr[0]);
		memcpy(&hat_adv_data[HAT_ADV_NAME_OFFSET + HAT_ADV_NAME_PREFIX_LEN], suffix, HAT_ADV_NAME_SUFFIX_LEN);
		le_adv_set_param(GAP_PARAM_ADV_DATA, sizeof(hat_adv_data), hat_adv_data);

		uint8_t device_name[GAP_DEVICE_NAME_LEN];
		snprintf((char *)device_name, GAP_DEVICE_NAME_LEN, HAT_ADV_NAME_PREFIX "%s", suffix);
		le_set_gap_param(GAP_PARAM_DEVICE_NAME, GAP_DEVICE_NAME_LEN, device_name);

		printf("\r\n[ble_provisioning] Advertising as: %s\r\n", device_name);
		le_adv_start();
	}
	gap_dev_state = new_state;
}

static void app_handle_conn_state_evt(uint8_t conn_id, T_GAP_CONN_STATE new_state, uint16_t disc_cause)
{
	(void)conn_id;
	if (new_state == GAP_CONN_STATE_DISCONNECTED) {
		printf("\r\n[ble_provisioning] disconnected, cause 0x%x — resume advertising\r\n", disc_cause);
		le_adv_start();
	} else if (new_state == GAP_CONN_STATE_CONNECTED) {
		printf("\r\n[ble_provisioning] connected\r\n");
	}
	gap_conn_state = new_state;
}

static void app_handle_authen_state_evt(uint8_t conn_id, uint8_t new_state, uint16_t cause)
{
	(void)conn_id;
	(void)new_state;
	(void)cause;
}

static void app_handle_gap_msg(T_IO_MSG *p_gap_msg)
{
	T_LE_GAP_MSG gap_msg;
	memcpy(&gap_msg, &p_gap_msg->u.param, sizeof(p_gap_msg->u.param));

	switch (p_gap_msg->subtype) {
	case GAP_MSG_LE_DEV_STATE_CHANGE:
		app_handle_dev_state_evt(gap_msg.msg_data.gap_dev_state_change.new_state,
								  gap_msg.msg_data.gap_dev_state_change.cause);
		break;
	case GAP_MSG_LE_CONN_STATE_CHANGE:
		app_handle_conn_state_evt(gap_msg.msg_data.gap_conn_state_change.conn_id,
								   (T_GAP_CONN_STATE)gap_msg.msg_data.gap_conn_state_change.new_state,
								   gap_msg.msg_data.gap_conn_state_change.disc_cause);
		break;
	case GAP_MSG_LE_AUTHEN_STATE_CHANGE:
		app_handle_authen_state_evt(gap_msg.msg_data.gap_authen_state.conn_id,
									 gap_msg.msg_data.gap_authen_state.new_state,
									 gap_msg.msg_data.gap_authen_state.status);
		break;
	default:
		break;
	}
}

void app_handle_io_msg(T_IO_MSG io_msg)
{
	if (io_msg.type == IO_MSG_TYPE_BT_STATUS) {
		app_handle_gap_msg(&io_msg);
	}
}

static void app_le_gap_init(void)
{
	uint8_t device_name[GAP_DEVICE_NAME_LEN] = HAT_ADV_NAME_PREFIX "0000";
	uint16_t appearance = GAP_GATT_APPEARANCE_UNKNOWN;
	uint8_t slave_init_mtu_req = false;

	uint8_t auth_pair_mode = GAP_PAIRING_MODE_NO_PAIRING; // see file header comment
	uint16_t auth_flags = 0;
	uint8_t auth_io_cap = GAP_IO_CAP_NO_INPUT_NO_OUTPUT;
	uint8_t auth_sec_req_enable = false;
	uint16_t auth_sec_req_flags = 0;

	le_set_gap_param(GAP_PARAM_DEVICE_NAME, GAP_DEVICE_NAME_LEN, device_name);
	le_set_gap_param(GAP_PARAM_APPEARANCE, sizeof(appearance), &appearance);
	le_set_gap_param(GAP_PARAM_SLAVE_INIT_GATT_MTU_REQ, sizeof(slave_init_mtu_req), &slave_init_mtu_req);

	uint8_t adv_evt_type = GAP_ADTYPE_ADV_IND;
	uint8_t adv_direct_type = GAP_REMOTE_ADDR_LE_PUBLIC;
	uint8_t adv_direct_addr[GAP_BD_ADDR_LEN] = {0};
	uint8_t adv_chann_map = GAP_ADVCHAN_ALL;
	uint8_t adv_filter_policy = GAP_ADV_FILTER_ANY;
	uint16_t adv_int_min = DEFAULT_ADVERTISING_INTERVAL_MIN;
	uint16_t adv_int_max = DEFAULT_ADVERTISING_INTERVAL_MAX;

	le_adv_set_param(GAP_PARAM_ADV_EVENT_TYPE, sizeof(adv_evt_type), &adv_evt_type);
	le_adv_set_param(GAP_PARAM_ADV_DIRECT_ADDR_TYPE, sizeof(adv_direct_type), &adv_direct_type);
	le_adv_set_param(GAP_PARAM_ADV_DIRECT_ADDR, sizeof(adv_direct_addr), adv_direct_addr);
	le_adv_set_param(GAP_PARAM_ADV_CHANNEL_MAP, sizeof(adv_chann_map), &adv_chann_map);
	le_adv_set_param(GAP_PARAM_ADV_FILTER_POLICY, sizeof(adv_filter_policy), &adv_filter_policy);
	le_adv_set_param(GAP_PARAM_ADV_INTERVAL_MIN, sizeof(adv_int_min), &adv_int_min);
	le_adv_set_param(GAP_PARAM_ADV_INTERVAL_MAX, sizeof(adv_int_max), &adv_int_max);
	le_adv_set_param(GAP_PARAM_ADV_DATA, sizeof(hat_adv_data), (void *)hat_adv_data);
	le_adv_set_param(GAP_PARAM_SCAN_RSP_DATA, sizeof(scan_rsp_data), (void *)scan_rsp_data);

	gap_set_param(GAP_PARAM_BOND_PAIRING_MODE, sizeof(auth_pair_mode), &auth_pair_mode);
	gap_set_param(GAP_PARAM_BOND_AUTHEN_REQUIREMENTS_FLAGS, sizeof(auth_flags), &auth_flags);
	gap_set_param(GAP_PARAM_BOND_IO_CAPABILITIES, sizeof(auth_io_cap), &auth_io_cap);
	le_bond_set_param(GAP_PARAM_BOND_SEC_REQ_ENABLE, sizeof(auth_sec_req_enable), &auth_sec_req_enable);
	le_bond_set_param(GAP_PARAM_BOND_SEC_REQ_REQUIREMENT, sizeof(auth_sec_req_flags), &auth_sec_req_flags);

	le_register_app_cb(app_gap_callback);
	vendor_cmd_init(app_vendor_callback);
}

static void app_le_profile_init(void)
{
	server_init(1);
	ble_provisioning_service_add((void *)app_profile_callback);
	server_register_app_cb(app_profile_callback);
}

static int ble_provisioning_stack_main(void)
{
	bt_trace_init();
	bt_stack_config_init();
	bte_init();
	board_init();
	le_gap_init(APP_MAX_LINKS);
	app_le_gap_init();
	app_le_profile_init();
	pwr_mgr_init();
	task_init();
	return 0;
}

extern bool rtk_bt_pre_enable(void);

static void ble_provisioning_init_task(void *param)
{
	(void)param;

	// The stack-ready callback starts advertising; the worker must exist first.
	if (!ble_provisioning_task_init()) {
		printf("\r\n[ble_provisioning] worker init failed; BLE disabled\r\n");
		vTaskDelete(NULL);
		return;
	}
	// The controller shares Wi-Fi hardware. Both initialization tasks start
	// after the scheduler; wait for the same readiness condition used by HCI.
	TickType_t wifi_started = xTaskGetTickCount();
	while (!(wifi_is_running(WLAN0_IDX) || wifi_is_running(WLAN1_IDX))) {
		if ((TickType_t)(xTaskGetTickCount() - wifi_started) >= pdMS_TO_TICKS(10000)) {
			printf("\r\n[ble_provisioning] Wi-Fi hardware init timed out; BLE disabled\r\n");
			vTaskDelete(NULL);
			return;
		}
		vTaskDelay(pdMS_TO_TICKS(50));
	}
	T_GAP_DEV_STATE new_state;
	if (rtk_bt_pre_enable() == false) {
		printf("\r\n[ble_provisioning] rtk_bt_pre_enable failed\r\n");
		vTaskDelete(NULL);
		return;
	}
	le_get_gap_param(GAP_PARAM_DEV_STATE, &new_state);
	if (new_state.gap_init_state != GAP_INIT_STATE_STACK_READY) {
		ble_provisioning_stack_main();
		bt_coex_init();

		do {
			os_delay(100);
			le_get_gap_param(GAP_PARAM_DEV_STATE, &new_state);
		} while (new_state.gap_init_state != GAP_INIT_STATE_STACK_READY);
	}

	vTaskDelete(NULL);
}

void ble_provisioning_start(void)
{
	if (xTaskCreate(ble_provisioning_init_task, (const char *)"ble_provisioning_init", 2048, NULL,
					tskIDLE_PRIORITY + 1, NULL) != pdPASS) {
		printf("\r\n[ble_provisioning] ble_provisioning_init_task: Create Task Error\r\n");
	}
}

// component/at_cmd/atcmd_bt.c (generic, unconditionally-linked serial
// AT-command dispatcher) calls these three by name whenever
// CONFIG_BT_PERIPHERAL is on — they used to live in the stock
// ble_app_main.c/ble_peripheral_at_cmd.c files this project no longer
// compiles (see application.cmake). Nothing in this firmware's actual
// operation drives BT over hand-typed serial AT commands, so these are
// link-satisfying stubs, not real reimplementations.
int ble_app_init(void)
{
	ble_provisioning_start();
	return 0;
}

void ble_app_deinit(void)
{
	printf("\r\n[ble_provisioning] ble_app_deinit: not supported (AT-command compat stub)\r\n");
}

int ble_peripheral_at_cmd_set_adv_int(int argc, char **argv)
{
	(void)argc;
	(void)argv;
	printf("\r\n[ble_provisioning] ATBLE adv-interval command: not supported (AT-command compat stub)\r\n");
	return -1;
}

#endif // CONFIG_BT_PERIPHERAL
