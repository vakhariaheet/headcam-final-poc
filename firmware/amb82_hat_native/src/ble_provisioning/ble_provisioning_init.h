#pragma once

// Brings up the BLE stack, registers the FFE0 provisioning service, and
// starts advertising as "UmpireHat_XXXX" (XXXX = last 2 bytes of the BT
// MAC). Call once from app_example(); Wi-Fi only connects once a
// SET_STA command arrives over BLE.
//
// Returns immediately, same contract as hat_pipeline_start(): the actual
// (blocking, ~ms-scale busy-wait) stack bring-up runs inside its own
// FreeRTOS task, started only once the scheduler is already running —
// app_example() itself runs before vTaskStartScheduler() (see main.c), and
// the BT stack's own internal tasks need the scheduler live to make
// progress, so blocking synchronously right here would deadlock.
void ble_provisioning_start(void);
