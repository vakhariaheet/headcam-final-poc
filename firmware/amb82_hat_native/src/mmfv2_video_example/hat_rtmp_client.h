#pragma once
#include "hat_h264.h"
#define HAT_RTMP_URL_MAX 384
// This version supports RTMP over TCP, H.264 video only, no B frames.
typedef struct hat_rtmp_client hat_rtmp_client;
bool hat_rtmp_url_valid(const char *url);
hat_rtmp_client *hat_rtmp_open(const char *url);
void hat_rtmp_close(hat_rtmp_client *client);
bool hat_rtmp_has_video(const hat_rtmp_client *client);
bool hat_rtmp_poll(hat_rtmp_client *client);
// Keep the RTMP session/timeline, but skip dependent frames until a fresh IDR.
void hat_rtmp_resync(hat_rtmp_client *client);
// Dropped/non-IDR frames before the first sequence header are not errors.
bool hat_rtmp_video(hat_rtmp_client *client, const uint8_t *annexb, size_t size, uint32_t timestamp);
