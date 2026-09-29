#include "hat_rtmp_client.h"
#include "hat_rtmp_transport.h"
#define NO_CRYPTO
#include "../../third_party/librtmp/rtmp.h"
#include "../../third_party/librtmp/log.h"
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
struct hat_rtmp_client {
    RTMP *rtmp;
    char url[HAT_RTMP_URL_MAX];
    hat_avc_t avc;
    uint8_t *body;
    bool started;
    uint32_t start_timestamp;
};
static void quiet_log(int level, const char *format, va_list args)
{
    // Protocol debug logs can contain the stream key. Public state is logged
    // by the publisher instead, without URLs or server command payloads.
    (void)level; (void)format; (void)args;
}
bool hat_rtmp_url_valid(const char *url)
{
    if (!url || strncmp(url, "rtmp://", 7) || strlen(url) >= HAT_RTMP_URL_MAX) return false;
    const char *path = strchr(url + 7, '/');
    if (!path || path == url + 7 || !path[1]) return false;
    const char *stream = strchr(path + 1, '/');
    if (!stream || !stream[1]) return false;
    // SetupURL also accepts space-delimited options: prohibit that syntax.
    for (const unsigned char *p = (const unsigned char *)url; *p; p++) {
        if (*p <= 32 || *p == 127) return false;
    }
    return true;
}
hat_rtmp_client *hat_rtmp_open(const char *url)
{
    if (!hat_rtmp_url_valid(url)) return NULL;
    hat_rtmp_client *c = calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->rtmp = RTMP_Alloc();
    c->body = malloc(HAT_MAX_FRAME + 4096);
    if (!c->rtmp || !c->body) {
        free(c->rtmp); free(c->body); free(c); return NULL;
    }
    RTMP_Init(c->rtmp);
    RTMP_LogSetCallback(quiet_log);
    strcpy(c->url, url);
    if (!RTMP_SetupURL(c->rtmp, c->url)) goto fail;
    c->rtmp->Link.timeout = 5;
    RTMP_EnableWrite(c->rtmp);
    if (!RTMP_Connect(c->rtmp, NULL) || !RTMP_ConnectStream(c->rtmp, 0)) goto fail;
    return c;
fail:
    hat_rtmp_close(c); return NULL;
}
void hat_rtmp_close(hat_rtmp_client *c)
{
    if (!c) return;
    RTMP_Close(c->rtmp); RTMP_Free(c->rtmp);
    free(c->body); free(c);
}
bool hat_rtmp_has_video(const hat_rtmp_client *c) { return c->started; }
bool hat_rtmp_poll(hat_rtmp_client *c)
{
    if (!RTMP_IsConnected(c->rtmp)) return false;
    // Drain bounded work per iteration; librtmp handles acknowledgements and ping.
    for (int i = 0; i < 8; i++) {
        int ready = hat_rtmp_readable(RTMP_Socket(c->rtmp));
        if (ready < 0) return false;
        if (!ready && c->rtmp->m_sb.sb_size == 0) break;
        RTMPPacket packet = {0};
        // On read failure librtmp may already have closed/freed channel state.
        if (!RTMP_ReadPacket(c->rtmp, &packet)) return false;
        if (RTMPPacket_IsReady(&packet)) RTMP_ClientPacket(c->rtmp, &packet);
        RTMPPacket_Free(&packet);
        if (!RTMP_IsConnected(c->rtmp)) return false;
    }
    return true;
}
static bool send_video(hat_rtmp_client *c, const uint8_t *body, size_t size, uint32_t timestamp)
{
    RTMPPacket packet = {0};
    if (!RTMPPacket_Alloc(&packet, size)) return false;
    memcpy(packet.m_body, body, size);
    packet.m_packetType = RTMP_PACKET_TYPE_VIDEO;
    packet.m_nChannel = 4;
    packet.m_headerType = RTMP_PACKET_SIZE_LARGE;
    packet.m_nTimeStamp = timestamp;
    packet.m_nInfoField2 = c->rtmp->m_stream_id;
    packet.m_nBodySize = size;
    bool ok = RTMP_SendPacket(c->rtmp, &packet, 0) != 0;
    RTMPPacket_Free(&packet);
    return ok;
}
bool hat_rtmp_video(hat_rtmp_client *c, const uint8_t *annexb, size_t size, uint32_t timestamp)
{
    size_t written;
    bool keyframe;
    if (!hat_avc_frame(&c->avc, annexb, size, c->body, HAT_MAX_FRAME + 4096, &written, &keyframe)) return false;
    if (!written) return true;
    if (!c->started || c->avc.changed) {
        if (!keyframe) return true;
        uint8_t sequence[528];
        size_t length = hat_avc_sequence(&c->avc, sequence, sizeof(sequence));
        if (!length) return true;
        if (!c->started) c->start_timestamp = timestamp;
        if (!send_video(c, sequence, length, timestamp - c->start_timestamp)) return false;
        c->started = true; c->avc.changed = false;
    }
    return send_video(c, c->body, written, timestamp - c->start_timestamp);
}
