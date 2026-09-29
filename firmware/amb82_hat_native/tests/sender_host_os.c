// Minimal pthread-backed RTOS shim for running the real publisher state machine.
#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>
struct host_queue {
    pthread_mutex_t lock;
    pthread_cond_t ready;
    unsigned capacity, count, head;
    size_t size;
    uint8_t *data;
};
QueueHandle_t xQueueCreate(unsigned n, size_t size) {
    QueueHandle_t q=calloc(1,sizeof(*q)); if (!q) return NULL;
    q->data=calloc(n,size); if (!q->data) { free(q); return NULL; }
    q->capacity=n; q->size=size;
    pthread_mutex_init(&q->lock,NULL); pthread_cond_init(&q->ready,NULL); return q;
}
void vQueueDelete(QueueHandle_t q) {
    pthread_mutex_destroy(&q->lock); pthread_cond_destroy(&q->ready); free(q->data); free(q);
}
int xQueueSend(QueueHandle_t q,const void *item,unsigned wait) {
    (void)wait; pthread_mutex_lock(&q->lock);
    int ok=q->count<q->capacity;
    if (ok) { memcpy(q->data+((q->head+q->count)%q->capacity)*q->size,item,q->size); q->count++; pthread_cond_signal(&q->ready); }
    pthread_mutex_unlock(&q->lock); return ok;
}
int xQueueReceive(QueueHandle_t q,void *item,unsigned wait) {
    pthread_mutex_lock(&q->lock);
    struct timespec until; clock_gettime(CLOCK_REALTIME,&until);
    until.tv_sec+=wait/1000; until.tv_nsec+=(wait%1000)*1000000;
    if (until.tv_nsec>=1000000000) { until.tv_sec++; until.tv_nsec-=1000000000; }
    while (!q->count && wait) { if (pthread_cond_timedwait(&q->ready,&q->lock,&until)) break; }
    int ok=q->count>0;
    if (ok) { memcpy(item,q->data+q->head*q->size,q->size); q->head=(q->head+1)%q->capacity; q->count--; }
    pthread_mutex_unlock(&q->lock); return ok;
}
SemaphoreHandle_t xSemaphoreCreateMutex(void) {
    SemaphoreHandle_t m=malloc(sizeof(*m)); if (m) pthread_mutex_init(m,NULL); return m;
}
void vSemaphoreDelete(SemaphoreHandle_t m) { pthread_mutex_destroy(m); free(m); }
int xSemaphoreTake(SemaphoreHandle_t m,unsigned wait) { (void)wait; return pthread_mutex_lock(m)==0; }
int xSemaphoreGive(SemaphoreHandle_t m) { return pthread_mutex_unlock(m)==0; }
struct task_call { void (*fn)(void *); void *arg; };
static void *thread(void *arg) { struct task_call call=*(struct task_call *)arg; free(arg); call.fn(call.arg); return NULL; }
int xTaskCreate(void (*fn)(void *),const char *name,unsigned stack,void *arg,unsigned priority,void *handle) {
    (void)name;(void)stack;(void)priority;(void)handle;
    struct task_call *call=malloc(sizeof(*call)); if (!call) return 0;
    call->fn=fn;call->arg=arg; pthread_t id;
    if (pthread_create(&id,NULL,thread,call)) { free(call);return 0; }
    pthread_detach(id);return 1;
}
void vTaskDelay(unsigned milliseconds) {
    struct timespec pause={milliseconds/1000,(milliseconds%1000)*1000000}; nanosleep(&pause,NULL);
}
