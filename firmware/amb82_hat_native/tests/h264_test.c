#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "hat_h264.h"
int main(void)
{
    const uint8_t idr[] = {0,0,0,1,0x67,0x64,0,0x28,0xaa, 0,0,1,0x68,0xeb,0xec, 0,0,0,1,0x65,0x88,0x84};
    hat_avc_t state = {0};
    uint8_t out[128]; size_t n; bool key;
    assert(hat_avc_frame(&state,idr,sizeof(idr),out,sizeof(out),&n,&key));
    assert(key && n == 12 && out[0] == 0x17 && out[8] == 3 && out[9] == 0x65);
    assert(state.sps_len == 5 && state.pps_len == 3 && state.changed);
    assert(hat_avc_sequence(&state,out,sizeof(out)) == 24);
    assert(out[5] == 1 && out[6] == 0x64 && out[8] == 0x28 && out[9] == 0xff);
    state.changed = false;
    assert(hat_avc_frame(&state,idr,sizeof(idr),out,sizeof(out),&n,&key));
    assert(!state.changed);
    const uint8_t inter[] = {0,0,1,0x09,0xf0,0,0,1,0x41,0x88};
    assert(hat_avc_frame(&state,inter,sizeof(inter),out,sizeof(out),&n,&key));
    assert(!key && n == 11 && out[0] == 0x27);
    assert(!hat_avc_frame(&state,inter,sizeof(inter),out,5,&n,&key));
    const uint8_t invalid[] = {0,0,1,0xe5,0x88};
    assert(!hat_avc_frame(&state,invalid,sizeof(invalid),out,sizeof(out),&n,&key));
    const uint8_t short_sps[] = {0,0,1,0x67,1};
    assert(!hat_avc_frame(&state,short_sps,sizeof(short_sps),out,sizeof(out),&n,&key));
    assert(!hat_avc_frame(&state,idr,HAT_MAX_FRAME+1,out,sizeof(out),&n,&key));
    assert(!hat_avc_frame(&state,idr,0,out,sizeof(out),&n,&key));
    puts("H.264 packetizer tests passed");
}
