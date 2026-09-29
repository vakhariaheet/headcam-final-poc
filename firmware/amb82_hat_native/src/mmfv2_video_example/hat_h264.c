#include "hat_h264.h"
#include <string.h>
static size_t prefix(const uint8_t *p, size_t n)
{
    if (n >= 4 && !p[0] && !p[1] && !p[2] && p[3] == 1) return 4;
    if (n >= 3 && !p[0] && !p[1] && p[2] == 1) return 3;
    return 0;
}
static bool cache(uint8_t *dst, size_t *size, const uint8_t *src, size_t n, bool *changed)
{
    if (!n || n > 256) return false;
    if (*size != n || memcmp(dst, src, n)) {
        memcpy(dst, src, n); *size = n; *changed = true;
    }
    return true;
}
bool hat_avc_frame(hat_avc_t *avc, const uint8_t *in, size_t length,
                   uint8_t *out, size_t capacity, size_t *written, bool *keyframe)
{
    *written = 0; *keyframe = false;
    if (!length || length > HAT_MAX_FRAME || capacity < 5) return false;
    size_t pos = 0, used = 5;
    bool slice = false;
    // Annex-B permits leading_zero_8bits before the first start code.
    while (pos < length && !prefix(in + pos, length - pos) && in[pos] == 0) pos++;
    while (pos < length) {
        size_t start = prefix(in + pos, length - pos);
        if (!start) return false;
        pos += start;
        size_t end = pos;
        while (end < length && !prefix(in + end, length - end)) end++;
        size_t n = end - pos;
        while (n && in[pos + n - 1] == 0) n--;
        if (!n || (in[pos] & 0x80)) return false;
        unsigned type = in[pos] & 31;
        if (type == 7) {
            if (n < 4 || !cache(avc->sps, &avc->sps_len, in + pos, n, &avc->changed)) return false;
        } else if (type == 8) {
            if (!cache(avc->pps, &avc->pps_len, in + pos, n, &avc->changed)) return false;
        } else if (type != 9) {
            if (type == 0 || type > 23 || n + 4 > capacity - used) return false;
            out[used++] = n >> 24; out[used++] = n >> 16;
            out[used++] = n >> 8; out[used++] = n;
            memcpy(out + used, in + pos, n); used += n;
            if (type == 5) *keyframe = true;
            if (type == 1 || type == 5) slice = true;
        }
        pos = end;
    }
    if (!slice) return true;
    out[0] = *keyframe ? 0x17 : 0x27;
    out[1] = 1; out[2] = out[3] = out[4] = 0;
    *written = used;
    return true;
}
size_t hat_avc_sequence(const hat_avc_t *avc, uint8_t *out, size_t capacity)
{
    size_t n = 16 + avc->sps_len + avc->pps_len;
    if (avc->sps_len < 4 || !avc->pps_len || capacity < n) return 0;
    uint8_t head[] = {0x17, 0, 0, 0, 0, 1, avc->sps[1], avc->sps[2], avc->sps[3], 0xff, 0xe1};
    memcpy(out, head, sizeof(head));
    size_t pos = sizeof(head);
    out[pos++] = avc->sps_len >> 8; out[pos++] = avc->sps_len;
    memcpy(out + pos, avc->sps, avc->sps_len); pos += avc->sps_len;
    out[pos++] = 1;
    out[pos++] = avc->pps_len >> 8; out[pos++] = avc->pps_len;
    memcpy(out + pos, avc->pps, avc->pps_len);
    return n;
}
