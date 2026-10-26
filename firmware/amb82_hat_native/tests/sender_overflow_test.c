// Block one send, overflow the real six-frame queue, and verify no reconnect.
#include "module_hat_rtmp.h"
#include "hat_rtmp_client.h"
#include "hat_rtmp_transport.h"
#include "FreeRTOS.h"
#include <pthread.h>
#include <assert.h>
#include <stdio.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned opens, closes, sends, resyncs;
static bool entered, release_send;
static int client_storage;
bool hat_rtmp_url_valid(const char *url) { return url != NULL; }
hat_rtmp_client *hat_rtmp_open(const char *url) {
    (void)url; pthread_mutex_lock(&lock); opens++; pthread_mutex_unlock(&lock);
    return (hat_rtmp_client *)&client_storage;
}
void hat_rtmp_close(hat_rtmp_client *c) {
    if (!c) return;
    pthread_mutex_lock(&lock); closes++; pthread_mutex_unlock(&lock);
}
bool hat_rtmp_has_video(const hat_rtmp_client *c) { (void)c; return true; }
bool hat_rtmp_poll(hat_rtmp_client *c) { (void)c; return true; }
void hat_rtmp_resync(hat_rtmp_client *c) {
    (void)c; pthread_mutex_lock(&lock); resyncs++; pthread_mutex_unlock(&lock);
}
bool hat_rtmp_video(hat_rtmp_client *c,const uint8_t *data,size_t n,uint32_t ts) {
    (void)c;(void)data;(void)n;(void)ts;
    pthread_mutex_lock(&lock); entered=true;
    while (!release_send) {
        pthread_mutex_unlock(&lock); vTaskDelay(1); pthread_mutex_lock(&lock);
    }
    sends++; pthread_mutex_unlock(&lock); return true;
}
bool ble_provisioning_service_notify_status(uint8_t conn,const char *json,uint16_t len) {
    (void)conn;(void)json;(void)len; return true;
}
static void wait_stage(unsigned stage) {
    uint32_t start=hat_rtmp_now();
    for (;;) {
        pthread_mutex_lock(&lock);
        bool ok=stage==0 ? entered : stage==1 ? resyncs>0 : stage==2 ? sends>=2 : closes>0;
        pthread_mutex_unlock(&lock);
        if (ok) return;
        assert((uint32_t)(hat_rtmp_now()-start)<3000); vTaskDelay(1);
    }
}
int main(void) {
    void *sink=hat_rtmp_module.create(NULL); assert(sink);
    hat_stream_camera_ready(); assert(hat_stream_start("rtmp://test/live/hat",0));
    uint8_t frame[]={0,0,1,0x65,0x88};
    mm_queue_item_t item={.data_addr=(uintptr_t)frame,.size=sizeof(frame)};
    // Wait until the sender has enabled frame acceptance.
    for (unsigned i=0;i<1000;i++) {
        hat_rtmp_module.handle(sink,&item,NULL);
        pthread_mutex_lock(&lock); bool ok=entered; pthread_mutex_unlock(&lock);
        if(ok) break;
        vTaskDelay(1);
    }
    wait_stage(0);
    for(unsigned i=0;i<20;i++)hat_rtmp_module.handle(sink,&item,NULL);
    pthread_mutex_lock(&lock); release_send=true; pthread_mutex_unlock(&lock);
    wait_stage(1);
    // Resync marks readiness just after the mock records its call.
    for(unsigned i=0;i<100;i++) {
        hat_rtmp_module.handle(sink,&item,NULL); vTaskDelay(1);
        pthread_mutex_lock(&lock); bool ok=sends>=2; pthread_mutex_unlock(&lock);
        if(ok) break;
    }
    wait_stage(2);
    pthread_mutex_lock(&lock); assert(opens==1 && closes==0); pthread_mutex_unlock(&lock);
    hat_stream_stop(0); wait_stage(3);
    puts("Overflow recovered on the same connection; STOP still closes it");
}
