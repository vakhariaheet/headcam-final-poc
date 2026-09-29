// Host regression tests exercise the real worker with an asynchronous fake pipeline.
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include "../src/ble_provisioning/ble_provisioning_task.c"

static bool fail_queue, fail_task, fail_send, pipeline_accept = true;
static bool queued;
static ble_provisioning_request_t queued_request;
static hat_pipeline_result_cb completion;
static jmp_buf worker_idle;
static int launches, notifications;
static uint8_t notified_connection;
static char last_status[256];

QueueHandle_t xQueueCreate(unsigned n, size_t size) {
    (void)n; assert(size == sizeof(queued_request));
    return fail_queue ? NULL : &queued_request;
}
void vQueueDelete(QueueHandle_t q) { assert(q); }
int xTaskCreate(void (*fn)(void *), const char *name, unsigned stack,
                void *arg, unsigned priority, void *handle) {
    (void)fn; (void)name; (void)stack; (void)arg; (void)priority; (void)handle;
    return !fail_task;
}
int xQueueSend(QueueHandle_t q, const void *request, unsigned wait) {
    assert(q); assert(wait == 0);
    if (fail_send) return 0;
    assert(!queued); memcpy(&queued_request, request, sizeof(queued_request));
    queued = true; return pdPASS;
}
int xQueueReceive(QueueHandle_t q, void *request, unsigned wait) {
    assert(q); (void)wait;
    if (!queued) longjmp(worker_idle, 1);
    memcpy(request, &queued_request, sizeof(queued_request));
    queued = false; return pdPASS;
}
bool hat_pipeline_start(const char *ssid, const char *pass, hat_pipeline_result_cb cb) {
    assert(strcmp(ssid, "test-network") == 0);
    assert(strcmp(pass, "test-password") == 0);
    if (!pipeline_accept) return false;
    launches++; completion = cb; return true;
}
bool ble_provisioning_service_notify_status(uint8_t conn, const char *json, uint16_t len) {
    assert(len < sizeof(last_status));
    memcpy(last_status, json, len); last_status[len] = 0;
    notified_connection = conn; notifications++; return true;
}
static void run_worker(void) {
    if (setjmp(worker_idle) == 0) ble_provisioning_task(NULL);
}
static bool submit(uint8_t conn) {
    return ble_provisioning_request_connect(conn, "test-network", "test-password", NULL);
}
int main(void) {
    assert(!submit(1)); // no queue yet
    fail_queue = true; assert(!ble_provisioning_task_init()); fail_queue = false;
    fail_task = true; assert(!ble_provisioning_task_init()); assert(!submit(1));
    fail_task = false; assert(ble_provisioning_task_init());
    assert(!ble_provisioning_request_connect(1, "", "test-password", NULL));
    assert(!ble_provisioning_request_connect(1, "123456789012345678901234567890123", "test-password", NULL));
    assert(!ble_provisioning_request_connect(1, "test-network", "short", NULL));
    fail_send = true; assert(!submit(1)); fail_send = false;
    assert(submit(1)); assert(!submit(2)); // queued attempt owns the slot
    run_worker(); assert(launches == 1); assert(!submit(2)); // in-flight attempt owns it too
    completion(false, NULL, "wifi_connect_timeout");
    assert(notifications == 1 && notified_connection == 1);
    assert(strstr(last_status, "wifi_connect_timeout"));
    assert(submit(2)); run_worker(); assert(launches == 2);
    completion(true, "192.0.2.1", NULL);
    assert(notified_connection == 2 && strstr(last_status, "connected"));
    pipeline_accept = false;
    assert(submit(3)); run_worker();
    assert(launches == 2 && notified_connection == 3);
    assert(strstr(last_status, "pipeline_active_restart_required"));
    assert(submit(3)); // rejected start released the reservation
    puts("Provisioning regression tests passed");
    return 0;
}
