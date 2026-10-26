#pragma once
#include "mmf2_module.h"

// Starts a task that notifies a subscribed BLE client on FFE2 every two
// seconds with encoder bitrate, sent bitrate, encoder FPS, Wi-Fi RSSI, and
// publisher state. Battery and temperature are not measurable on this board.
// Call once after the video module is running; later calls are ignored.
void hat_telemetry_start(mm_context_t *video_ctx, int video_channel);
