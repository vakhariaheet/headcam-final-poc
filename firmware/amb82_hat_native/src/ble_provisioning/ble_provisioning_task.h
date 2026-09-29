#pragma once

#include <stdbool.h>
#include <stdint.h>

// Create the worker before the BLE stack can advertise. False on allocation failure.
bool ble_provisioning_task_init(void);

// Reserve one provisioning attempt. Reject invalid credentials, an unavailable
// worker, or a request while an earlier attempt is still running.
bool ble_provisioning_request_connect(uint8_t conn_id, const char *ssid, const char *pass,
                                     const char *session_token);
