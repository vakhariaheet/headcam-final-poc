#include "module_hat_rtmp.h"
#include "hat_rtmp_client.h"
#include "hat_rtmp_transport.h"
#include "ble_provisioning_service.h"
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#if __has_include("cloud_config.h")
#include "cloud_config.h"
#else
#include "cloud_config.example.h"
#endif

#define FRAME_QUEUE_DEPTH 6
typedef struct {
    uint8_t *bytes;
    size_t size;
    uint32_t timestamp, generation;
} queued_frame;
typedef struct {
    SemaphoreHandle_t lock;
    QueueHandle_t frames;
    bool ready, desired, accepting, discontinuity;
    uint32_t generation, sender_generation;
    uint8_t conn_id;
    char url[HAT_RTMP_URL_MAX];
} publisher;
static publisher *instance;

static bool is_cancelled(void *arg)
{
    publisher *p = arg;
    xSemaphoreTake(p->lock, portMAX_DELAY);
    bool result = !p->desired || p->generation != p->sender_generation;
    xSemaphoreGive(p->lock);
    return result;
}
static void report(publisher *p, uint32_t generation, const char *status)
{
    char json[96];
    xSemaphoreTake(p->lock, portMAX_DELAY);
    bool current = p->generation == generation;
    uint8_t conn_id = p->conn_id;
    xSemaphoreGive(p->lock);
    if (!current) return;
    printf("\r\n[hat-stream] %s\r\n", status);
    int size = snprintf(json, sizeof(json), "{\"event\":\"stream\",\"status\":\"%s\"}", status);
    ble_provisioning_service_notify_status(conn_id, json, (uint16_t)size);
}
static void drain(publisher *p)
{
    queued_frame frame;
    while (xQueueReceive(p->frames, &frame, 0) == pdPASS) free(frame.bytes);
}
static void sender(void *arg)
{
    publisher *p = arg;
    hat_rtmp_set_cancel(is_cancelled, p);
    unsigned backoff = 1000;
    uint32_t observed_generation = 0;
    for (;;) {
        char url[HAT_RTMP_URL_MAX];
        xSemaphoreTake(p->lock, portMAX_DELAY);
        bool desired = p->desired;
        uint32_t generation = p->generation;
        if (desired) {
            strcpy(url, p->url);
            p->sender_generation = generation;
        }
        xSemaphoreGive(p->lock);
        if (!desired) {
            if (observed_generation != generation) report(p, generation, "stopped");
            observed_generation = generation;
            backoff = 1000;
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }
        if (generation != observed_generation) backoff = 1000;
        observed_generation = generation;
        report(p, generation, "connecting");
        hat_rtmp_client *client = hat_rtmp_open(url);
        bool published = false;
        if (client && !is_cancelled(p)) {
            xSemaphoreTake(p->lock, portMAX_DELAY);
            p->accepting = p->generation == generation && p->desired;
            p->discontinuity = false;
            xSemaphoreGive(p->lock);
            while (!is_cancelled(p)) {
                xSemaphoreTake(p->lock, portMAX_DELAY);
                bool broken = p->discontinuity;
                xSemaphoreGive(p->lock);
                if (broken || !hat_rtmp_poll(client)) break;
                queued_frame frame;
                if (xQueueReceive(p->frames, &frame, pdMS_TO_TICKS(100)) != pdPASS) continue;
                bool ok = frame.generation == generation && !is_cancelled(p) &&
                    hat_rtmp_video(client, frame.bytes, frame.size, frame.timestamp);
                free(frame.bytes);
                if (!ok) break;
                if (!published && hat_rtmp_has_video(client)) {
                    published = true; backoff = 1000;
                    report(p, generation, "publishing");
                }
            }
        }
        xSemaphoreTake(p->lock, portMAX_DELAY);
        p->accepting = false;
        xSemaphoreGive(p->lock);
        hat_rtmp_close(client);
        drain(p);
        if (is_cancelled(p)) continue;
        report(p, generation, "reconnecting");
        // Interruptible backoff: STOP or a replacement START wins immediately.
        uint32_t began = hat_rtmp_now();
        while (!is_cancelled(p) && (uint32_t)(hat_rtmp_now() - began) < backoff) {
            vTaskDelay(pdMS_TO_TICKS(100));
        }
        if (backoff < 30000) backoff = backoff * 2 > 30000 ? 30000 : backoff * 2;
    }
}
void hat_stream_camera_ready(void)
{
    if (!instance) return;
    xSemaphoreTake(instance->lock, portMAX_DELAY);
    instance->ready = true;
    xSemaphoreGive(instance->lock);
}
bool hat_stream_start(const char *url, uint8_t conn_id)
{
    publisher *p = instance;
    if (!url || !url[0]) url = HAT_DEFAULT_RTMP_URL;
    if (!p || !hat_rtmp_url_valid(url)) return false;
    xSemaphoreTake(p->lock, portMAX_DELAY);
    if (!p->ready || p->desired) { xSemaphoreGive(p->lock); return false; }
    strcpy(p->url, url);
    p->conn_id = conn_id;
    p->desired = true;
    p->generation++;
    xSemaphoreGive(p->lock);
    return true;
}
void hat_stream_stop(uint8_t conn_id)
{
    publisher *p = instance;
    if (!p) {
        const char *json = "{\"event\":\"stream\",\"status\":\"stopped\"}";
        ble_provisioning_service_notify_status(conn_id, json, strlen(json));
        return;
    }
    xSemaphoreTake(p->lock, portMAX_DELAY);
    p->desired = false;
    p->accepting = false;
    p->conn_id = conn_id;
    p->generation++;
    xSemaphoreGive(p->lock);
}
static int handle(void *arg, void *input, void *output)
{
    (void)output;
    publisher *p = arg;
    mm_queue_item_t *item = input;
    xSemaphoreTake(p->lock, portMAX_DELAY);
    bool accept = p->desired && p->accepting;
    uint32_t generation = p->generation;
    xSemaphoreGive(p->lock);
    if (!accept) return 0;
    queued_frame frame = { .size = item->size, .timestamp = item->timestamp, .generation = generation };
    if (frame.size && frame.size <= HAT_MAX_FRAME) {
        frame.bytes = malloc(frame.size);
        if (frame.bytes) {
            memcpy(frame.bytes, (void *)item->data_addr, frame.size);
            if (xQueueSend(p->frames, &frame, 0) == pdPASS) return 0;
            free(frame.bytes);
        }
    }
    // A missing reference frame corrupts dependent pictures. Reconnect and
    // resume on a fresh SPS/PPS+IDR instead of sending a damaged GOP.
    xSemaphoreTake(p->lock, portMAX_DELAY);
    if (p->generation == generation) p->discontinuity = true;
    xSemaphoreGive(p->lock);
    return 0;
}
static void *create(void *parent)
{
    (void)parent;
    if (instance) return NULL;
    publisher *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    p->lock = xSemaphoreCreateMutex();
    p->frames = xQueueCreate(FRAME_QUEUE_DEPTH, sizeof(queued_frame));
    if (!p->lock || !p->frames ||
        xTaskCreate(sender, "hat_rtmp", 4096, p, tskIDLE_PRIORITY + 1, NULL) != pdPASS) {
        if (p->lock) vSemaphoreDelete(p->lock);
        if (p->frames) vQueueDelete(p->frames);
        free(p); return NULL;
    }
    instance = p;
    return p;
}
mm_module_t hat_rtmp_module = {
    .create = create,
    .handle = handle,
    .module_type = MM_TYPE_VSINK,
    .output_type = MM_TYPE_NONE,
    .name = "HAT_RTMP"
};
