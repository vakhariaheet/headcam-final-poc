// Host regression tests exercise the real worker with an asynchronous fake pipeline.
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include "../src/ble_provisioning/ble_provisioning_task.c"

static bool fail_queue, fail_task, fail_send, pipeline_accept = true;
static bool queued, has_saved;
static int timeouts_allowed;
static TickType_t now;
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
TickType_t xTaskGetTickCount(void) { return now; }
// Two-slot FIFO matching BLE_PROVISIONING_QUEUE_LEN.
static ble_provisioning_request_t second_request;
static bool second_queued;
int xQueueSend(QueueHandle_t q, const void *request, unsigned wait) {
    assert(q); assert(wait == 0);
    if (fail_send) return 0;
    if (!queued) { memcpy(&queued_request, request, sizeof(queued_request)); queued = true; }
    else { assert(!second_queued); memcpy(&second_request, request, sizeof(second_request)); second_queued = true; }
    return pdPASS;
}
// Empty queue: a bounded wait may time out (consuming one allowed timeout and
// advancing the clock past it); otherwise the worker is idle and the test resumes.
int xQueueReceive(QueueHandle_t q, void *request, unsigned wait) {
    assert(q);
    if (!queued) {
        if (wait == portMAX_DELAY || timeouts_allowed == 0) longjmp(worker_idle, 1);
        timeouts_allowed--; now += wait; return 0;
    }
    memcpy(request, &queued_request, sizeof(queued_request));
    queued = second_queued;
    if (second_queued) { queued_request = second_request; second_queued = false; }
    return pdPASS;
}
bool hat_wifi_store_load(hat_wifi_credentials_t *out) {
    if (!has_saved) return false;
    memset(out, 0, sizeof(*out));
    strcpy(out->ssid, "test-network"); strcpy(out->pass, "test-password");
    return true;
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

static void test_app_requests(void) {
    assert(!submit(1)); // no queue yet
    fail_queue = true; assert(!ble_provisioning_task_init()); fail_queue = false;
    fail_task = true; assert(!ble_provisioning_task_init()); assert(!submit(1));
    fail_task = false; assert(ble_provisioning_task_init());
    assert(!ble_provisioning_request_connect(1, "", "test-password", NULL));
    assert(!ble_provisioning_request_connect(1, "123456789012345678901234567890123", "test-password", NULL));
    assert(!ble_provisioning_request_connect(1, "test-network", "short", NULL));
    assert(!submit(BLE_PROVISIONING_NO_CONN)); // reserved for boot reconnects
    fail_send = true; assert(!submit(1)); fail_send = false;
    assert(submit(1)); assert(!submit(2)); // queued attempt owns the slot
    run_worker(); assert(launches == 1); assert(!submit(2)); // in-flight attempt owns it too
    completion(false, NULL, "wifi_connect_timeout");
    assert(notifications == 1 && notified_connection == 1);
    assert(strstr(last_status, "wifi_connect_timeout"));
    assert(!saved_retry_scheduled); // app failures never schedule saved retries
    assert(provisioning_owner == PROVISIONING_OWNER_NONE);
    assert(submit(2)); run_worker(); assert(launches == 2);
    completion(true, "192.0.2.1", NULL);
    assert(notified_connection == 2 && strstr(last_status, "connected"));
    pipeline_accept = false;
    assert(submit(3)); run_worker();
    assert(launches == 2 && notified_connection == 3);
    assert(strstr(last_status, "pipeline_busy_or_restart_required"));
    assert(submit(3)); // rejected start released the reservation
    run_worker(); pipeline_accept = true; // drain the rejected request
}

static void test_saved_network(void) {
    has_saved = false;
    assert(!ble_provisioning_request_saved_connect());
    has_saved = true;
    assert(ble_provisioning_request_saved_connect());
    assert(!ble_provisioning_request_saved_connect()); // one saved attempt at a time
    int before = launches;
    run_worker(); assert(launches == before + 1);
    completion(false, NULL, "wifi_connect_timeout");
    assert(notified_connection == BLE_PROVISIONING_NO_CONN);
    assert(saved_retry_scheduled && ble_provisioning_wait_ticks() == 15000);

    // Retry fires after the delay and relaunches; backoff doubles.
    timeouts_allowed = 1; run_worker();
    assert(launches == before + 2 && !saved_retry_scheduled);
    completion(false, NULL, "dhcp_failed");
    assert(saved_retry_scheduled && ble_provisioning_wait_ticks() == 30000);

    // An app request supersedes the pending retry.
    assert(submit(4)); run_worker();
    assert(launches == before + 3 && !saved_retry_scheduled);
    completion(true, "192.0.2.2", NULL);
    assert(notified_connection == 4 && !saved_retry_scheduled);

    // An app request takes over a saved attempt that is still associating.
    // The superseded saved result is ignored: no notification, no retry, and
    // it must not release the app's reservation.
    assert(ble_provisioning_request_saved_connect()); run_worker();
    hat_pipeline_result_cb saved_completion = completion;
    int notified_before = notifications;
    assert(submit(6)); assert(!submit(7)); // the app request now owns the worker
    run_worker(); assert(launches == before + 5);
    hat_pipeline_result_cb app_completion = completion;
    saved_completion(false, NULL, "superseded");
    assert(notifications == notified_before && !saved_retry_scheduled);
    assert(provisioning_owner == PROVISIONING_OWNER_APP);
    app_completion(true, "192.0.2.3", NULL);
    assert(notified_connection == 6 && strstr(last_status, "connected"));
    assert(provisioning_owner == PROVISIONING_OWNER_NONE);

    // A saved request still queued when the app takes over is dropped unrun.
    assert(ble_provisioning_request_saved_connect());
    assert(submit(8));
    int launches_before = launches;
    run_worker(); assert(launches == launches_before + 1); // only the app request ran
    completion(true, "192.0.2.4", NULL);
    assert(notified_connection == 8);

    // A pending retry is cancelled the moment an app request is accepted.
    assert(ble_provisioning_request_saved_connect()); run_worker();
    completion(false, NULL, "wifi_connect_timeout");
    assert(saved_retry_scheduled);
    assert(submit(9)); assert(!saved_retry_scheduled);
    run_worker(); completion(true, "192.0.2.5", NULL);

    // A rejected saved start (camera failed) stops retrying and frees the worker.
    pipeline_accept = false;
    assert(ble_provisioning_request_saved_connect()); run_worker();
    assert(!saved_retry_scheduled && submit(5));
    run_worker(); pipeline_accept = true;
}

int main(void) {
    test_app_requests();
    test_saved_network();
    puts("Provisioning regression tests passed");
    return 0;
}
