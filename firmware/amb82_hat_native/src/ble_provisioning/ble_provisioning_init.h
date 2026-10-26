#pragma once

#include <stdint.h>

// Brings up the BLE stack, registers the FFE0 provisioning service, and
// starts advertising as "UmpireHat_XXXX" (XXXX = last 2 bytes of the BT
// MAC). Call once from app_example(), after hat_control_start() has loaded
// ownership. Wi-Fi only connects once a SET_STA command arrives over BLE,
// or from the saved network.
//
// Returns immediately, same contract as hat_pipeline_start(): the actual
// (blocking, ~ms-scale busy-wait) stack bring-up runs inside its own
// FreeRTOS task, started only once the scheduler is already running —
// app_example() itself runs before vTaskStartScheduler() (see main.c), and
// the BT stack's own internal tasks need the scheduler live to make
// progress, so blocking synchronously right here would deadlock.
void ble_provisioning_start(void);

// The scan response carries service data for UUID
// AA8AEB53-18B8-4DF7-9C9B-4C579D9A9576 whose one byte holds these flags.
// The app labels scan results with them; see hat_ownership_protocol.dart.
#define HAT_ADV_FLAG_PAIRING 0x01 // pairing mode open: a phone may claim the hat
#define HAT_ADV_FLAG_OWNED   0x02 // an owner key exists

// Thread-safe requests executed on the BT task. No-ops before the stack runs.
void ble_provisioning_refresh_advertising(void);
void ble_provisioning_disconnect(uint8_t conn_id);
