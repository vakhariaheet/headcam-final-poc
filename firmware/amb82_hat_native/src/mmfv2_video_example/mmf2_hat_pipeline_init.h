#pragma once

#include <stdbool.h>

// Exactly one completion per accepted request. Success requires DHCP and, on
// the first request, encoder frames; failure supplies a short machine-readable reason.
typedef void (*hat_pipeline_result_cb)(bool success, const char *ip, const char *reason);

// Non-blocking, copies credentials. Before the camera runs, connects Wi-Fi and
// starts the camera. While it runs, switches networks instead (the same,
// still-associated network completes immediately); a failed switch keeps
// recovering the previous network. Successful networks are saved to flash.
// False while another request is pending, or after camera initialization
// failed (reset required). Association has a 30s deadline; DHCP uses the SDK timeout.
bool hat_pipeline_start(const char *ssid, const char *pass, hat_pipeline_result_cb result_cb);

typedef enum {
	HAT_PIPELINE_STATUS_IDLE,       // nothing in progress; waiting for a request
	HAT_PIPELINE_STATUS_CONNECTING, // first association/camera bring-up, or a switch pending
	HAT_PIPELINE_STATUS_RUNNING,    // camera up (Wi-Fi may still be recovering)
	HAT_PIPELINE_STATUS_FAILED,     // camera failed or stalled; reset required
} hat_pipeline_status_t;

// Snapshot for status display; safe from any task.
hat_pipeline_status_t hat_pipeline_status(void);
