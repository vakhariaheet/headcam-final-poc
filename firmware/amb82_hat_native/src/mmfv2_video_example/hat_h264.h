#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#define HAT_MAX_FRAME (512u * 1024u)
typedef struct {
    uint8_t sps[256], pps[256];
    size_t sps_len, pps_len;
    bool changed;
} hat_avc_t;
// Convert one Annex-B access unit to an FLV AVC video payload. SPS/PPS are cached,
// AUDs are omitted. Reject malformed/oversized data; no B-frame composition offset.
bool hat_avc_frame(hat_avc_t *avc, const uint8_t *in, size_t length,
                   uint8_t *out, size_t capacity, size_t *written, bool *keyframe);
size_t hat_avc_sequence(const hat_avc_t *avc, uint8_t *out, size_t capacity);
