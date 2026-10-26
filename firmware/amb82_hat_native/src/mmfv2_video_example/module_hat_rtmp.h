#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "mmf2_module.h"
extern mm_module_t hat_rtmp_module;
void hat_stream_camera_ready(void);
// Called after provisioning; URL may be empty to use cloud_config.h's default.
bool hat_stream_start(const char *url, uint8_t conn_id);
void hat_stream_stop(uint8_t conn_id);
// Video payload bytes accepted by the RTMP client (wraps at 4 GiB) and the
// last reported publisher state ("idle", "connecting", "publishing", ...).
void hat_stream_stats(uint32_t *sent_bytes, const char **state);
