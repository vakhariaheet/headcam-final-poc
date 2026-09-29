#pragma once

#include <stdbool.h>

// Exactly one completion per accepted request. Success requires DHCP and
// encoder frames; failure supplies a short machine-readable reason.
typedef void (*hat_pipeline_result_cb)(bool success, const char *ip, const char *reason);

// Non-blocking, copies credentials. False if a pipeline is already active or
// camera initialization previously failed (reset required). Wi-Fi failures
// permit retry. Association has a 30s deadline; DHCP uses the SDK timeout.
bool hat_pipeline_start(const char *ssid, const char *pass, hat_pipeline_result_cb result_cb);
