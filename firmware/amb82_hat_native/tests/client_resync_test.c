// Exercise the real packetizer/client with captured RTMP packets, no network.
#define RTMP_SendPacket capture_packet
#include "../src/mmfv2_video_example/hat_rtmp_client.c"
#include <assert.h>
#include <stdio.h>
static unsigned packets;
static uint32_t timestamps[8];
static unsigned types[8];
int capture_packet(RTMP *r, RTMPPacket *p, int queue)
{
    (void)r; (void)queue;
    assert(packets < 8);
    timestamps[packets] = p->m_nTimeStamp;
    types[packets++] = (uint8_t)p->m_body[1];
    return 1;
}
int main(void)
{
    const uint8_t idr[] = {0,0,1,0x67,0x64,0,0x28,0xaa,0,0,1,0x68,0xeb,0xec,0,0,1,0x65,0x88};
    const uint8_t inter[] = {0,0,1,0x41,0x88};
    hat_rtmp_client c = {0};
    c.rtmp = RTMP_Alloc(); assert(c.rtmp); RTMP_Init(c.rtmp);
    c.body = malloc(HAT_MAX_FRAME + 4096); assert(c.body);
    assert(hat_rtmp_video(&c,idr,sizeof(idr),1000));
    assert(packets == 2 && timestamps[0] == 0 && types[0] == 0);
    hat_rtmp_resync(&c);
    assert(hat_rtmp_has_video(&c));
    assert(hat_rtmp_video(&c,inter,sizeof(inter),1033));
    assert(packets == 2); // Dependent picture must not reach the decoder.
    assert(hat_rtmp_video(&c,idr,sizeof(idr),2000));
    assert(packets == 4 && types[2] == 0 && types[3] == 1);
    assert(timestamps[2] == 1000 && timestamps[3] == 1000);
    assert(hat_rtmp_video(&c,inter,sizeof(inter),2033));
    assert(packets == 5 && timestamps[4] == 1033);
    free(c.body); RTMP_Free(c.rtmp);
    puts("Client resync preserves timeline and skips dependent frames");
}
