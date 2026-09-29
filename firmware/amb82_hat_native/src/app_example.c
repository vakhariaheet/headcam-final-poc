// Replaces the SDK's own src/app_example.c. Called once from main() before
// the FreeRTOS scheduler starts (see main.c's main()); everything here just
// registers tasks, none of it runs yet.
//
// Phase 1's secrets.h-driven auto-connect is gone: hat_pipeline_start() is
// no longer called from here directly. It now only runs once
// ble_provisioning_task.c hands it real credentials from a BLE SET_STA
// write — see ble_provisioning/.
#include <stdio.h>
#include "wifi_fast_connect.h"
#include "ble_provisioning_init.h"

void app_example(void)
{
	// setup() enables SDK fast connect, but its Wi-Fi task has not run yet.
	// Provisioning owns credentials; do not load/save an unrelated flash profile.
	wifi_fast_connect_enable(0);
	printf("\r\n[hat] native provisioning build %s %s\r\n", __DATE__, __TIME__);
	ble_provisioning_start();
}
