#pragma once

#include <stdint.h>
#include "profile_server.h"

// Master Spec §4.2/§4.3 GATT layout, shared with the mobile app's
// real_hat_connection_service.dart. SET_STA provisions Wi-Fi;
// START_STREAM/STOP_STREAM reuse this FFE1/FFE2 pair for the
// outbound RTMP publisher.
#define GATT_UUID_HAT_PROVISIONING_SERVICE   0xFFE0
#define GATT_UUID_HAT_PROVISIONING_CMD       0xFFE1 // write
#define GATT_UUID_HAT_PROVISIONING_STATUS    0xFFE2 // read + notify

extern T_SERVER_ID ble_provisioning_service_id;

// Registers the FFE0 service (call once, from app_le_profile_init-equivalent
// init code, after server_init()). p_func is the app-level profile callback
// forwarded read/write/cccd events, same pattern as simp_ble_service_add_service.
T_SERVER_ID ble_provisioning_service_add(void *p_func);

// Pushes a status JSON string to a connected client on FFE2 (notify) and
// caches it as the value a subsequent read would also return.
bool ble_provisioning_service_notify_status(uint8_t conn_id, const char *json, uint16_t len);
