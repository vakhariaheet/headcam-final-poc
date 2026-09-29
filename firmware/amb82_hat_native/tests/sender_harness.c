#include "module_hat_rtmp.h"
#include "FreeRTOS.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
static uint8_t *video;
static size_t video_size;
static void *sink;
bool ble_provisioning_service_notify_status(uint8_t conn, const char *json, uint16_t len) {
    (void)conn; printf("STATUS %.*s\n",len,json); fflush(stdout); return true;
}
static size_t aud(const uint8_t *p,size_t n) {
    if(n>=5&&!p[0]&&!p[1]&&!p[2]&&p[3]==1&&(p[4]&31)==9)return 4;
    if(n>=4&&!p[0]&&!p[1]&&p[2]==1&&(p[3]&31)==9)return 3;
    return 0;
}
static void feed(void *arg) {
    (void)arg;size_t pos=0;uint32_t frames=0;
    for (;;) {
        if(pos==video_size)pos=0;
        size_t code=aud(video+pos,video_size-pos);assert(code);
        size_t end=pos+code+1;
        while(end<video_size&&!aud(video+end,video_size-end))end++;
        mm_queue_item_t item={.data_addr=(uintptr_t)(video+pos),.size=end-pos,.timestamp=frames++*1000/30};
        hat_rtmp_module.handle(sink,&item,NULL);pos=end;vTaskDelay(33);
    }
}
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    FILE *f=fopen(argv[1],"rb");if(!f)return 2;
    fseek(f,0,SEEK_END);video_size=ftell(f);rewind(f);
    video=malloc(video_size);assert(video);assert(fread(video,1,video_size,f)==video_size);fclose(f);
    sink=hat_rtmp_module.create(NULL);assert(sink);
    assert(!hat_stream_start("rtmp://127.0.0.1:19350/live/not-ready",0));
    hat_stream_camera_ready();
    assert(xTaskCreate(feed,"feed",0,NULL,0,NULL));
    puts("READY");fflush(stdout);
    char line[512];
    while(fgets(line,sizeof(line),stdin)) {
        line[strcspn(line,"\r\n")]=0;
        if(!strncmp(line,"start ",6))printf("ACCEPTED %d\n",hat_stream_start(line+6,0));
        else if(!strcmp(line,"stop"))hat_stream_stop(0);
        else if(!strcmp(line,"quit"))break;
        fflush(stdout);
    }
    return 0;
}
