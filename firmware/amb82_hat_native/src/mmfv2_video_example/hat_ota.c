// SDK glue for hat_ota_image.c: plain HTTP download over lwIP, the SDK's
// NOR slot writer, and progress notifications.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "hal.h"
#include "ota_8735b.h"
#include "wifi_conf.h"
#include "lwip/sockets.h"
#include "lwip/netdb.h"

#include "ble_provisioning_service.h"
#include "hat_ota.h"
#include "module_hat_rtmp.h"

// Not in ota_8735b.h, but non-static in ota_8735b.c and used the same way
// by its http_update_ota(). Withholds the slot's boot label until the final
// block and checks the trailing checksum against flash.
int ota_flash_NOR(uint32_t target_fw_idx, uint32_t total_blocks, uint32_t cur_block, uint8_t *buf,
				  uint32_t data_len, _file_checksum file_checksum);
// Defined in the SDK's prebuilt platform library; 0 means booted from NOR.
uint8_t sys_get_boot_sel(void);

#define HAT_OTA_RECV_TIMEOUT_MS 15000
#define HAT_OTA_HEAD_MAX 1024
#define HAT_OTA_VERSION_MAX 24
#define HAT_OTA_REBOOT_DELAY_MS 1500

typedef struct {
	char host[HAT_OTA_HOST_MAX];
	char path[HAT_OTA_PATH_MAX];
	char version[HAT_OTA_VERSION_MAX];
	uint16_t port;
	uint32_t size;
	uint8_t sha256[HAT_OTA_SHA256_LEN];
	uint32_t target_fw_idx;
	// Download state used by the read callback.
	int fd;
	char head[HAT_OTA_HEAD_MAX];
	size_t leftover_pos;
	size_t leftover_len;
	uint8_t reported;
} hat_ota_job_t;

static volatile bool hat_ota_running;
static hat_ota_job_t hat_ota_job;

bool hat_ota_in_progress(void)
{
	return hat_ota_running;
}

static void hat_ota_notify(const char *json)
{
	ble_provisioning_service_notify_event(json, (uint16_t)strlen(json));
}

static void hat_ota_notify_error(const char *reason)
{
	char json[96];
	snprintf(json, sizeof(json), "{\"event\":\"ota\",\"status\":\"error\",\"reason\":\"%s\"}", reason);
	printf("\r\n[hat-ota] failed: %s\r\n", reason);
	hat_ota_notify(json);
}

static int hat_ota_read(void *context, uint8_t *buf, size_t len)
{
	hat_ota_job_t *job = context;
	if (job->leftover_pos < job->leftover_len) {
		size_t n = job->leftover_len - job->leftover_pos;
		if (n > len) n = len;
		memcpy(buf, job->head + job->leftover_pos, n);
		job->leftover_pos += n;
		return (int)n;
	}
	return recv(job->fd, buf, len, 0);
}

static int hat_ota_flash(void *context, uint32_t total_blocks, uint32_t block, uint8_t *buf, uint32_t len,
						 const uint8_t checksum[4])
{
	hat_ota_job_t *job = context;
	_file_checksum file_checksum;
	memcpy(file_checksum.c, checksum, sizeof(file_checksum.c));
	return ota_flash_NOR(job->target_fw_idx, total_blocks, block, buf, len, file_checksum) < 0 ? -1 : 0;
}

static void hat_ota_progress(void *context, uint8_t percent)
{
	hat_ota_job_t *job = context;
	if (percent / 10 == job->reported / 10) return;
	job->reported = percent;
	char json[64];
	snprintf(json, sizeof(json), "{\"event\":\"ota\",\"status\":\"downloading\",\"progress\":%u}", percent);
	hat_ota_notify(json);
}

static int hat_ota_connect(const hat_ota_job_t *job)
{
	char port[6];
	snprintf(port, sizeof(port), "%u", job->port);
	struct addrinfo hints;
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_STREAM;
	struct addrinfo *result = NULL;
	if (getaddrinfo(job->host, port, &hints, &result) != 0 || !result) return -1;

	int fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd >= 0) {
		int timeout_ms = HAT_OTA_RECV_TIMEOUT_MS; // lwIP takes milliseconds here (SNDRCVTIMEO_NONSTANDARD)
		setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout_ms, sizeof(timeout_ms));
		setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout_ms, sizeof(timeout_ms));
		if (connect(fd, result->ai_addr, result->ai_addrlen) != 0) {
			close(fd);
			fd = -1;
		}
	}
	freeaddrinfo(result);
	return fd;
}

static bool hat_ota_send_all(int fd, const char *data, size_t len)
{
	while (len > 0) {
		int sent = send(fd, data, len, 0);
		if (sent <= 0) return false;
		data += sent;
		len -= (size_t)sent;
	}
	return true;
}

// Sends the GET and reads the response head; leaves any body bytes that
// arrived with it in job->head for hat_ota_read().
static const char *hat_ota_request(hat_ota_job_t *job)
{
	char request[HAT_OTA_PATH_MAX + HAT_OTA_HOST_MAX + 96];
	int len = snprintf(request, sizeof(request),
					   "GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\nUser-Agent: UmpireHat/%s\r\n\r\n",
					   job->path, job->host, job->version);
	if (len <= 0 || len >= (int)sizeof(request) || !hat_ota_send_all(job->fd, request, (size_t)len)) {
		return "download_failed";
	}

	size_t have = 0;
	for (;;) {
		if (have == sizeof(job->head)) return "download_failed"; // head too large
		int got = recv(job->fd, job->head + have, sizeof(job->head) - have, 0);
		if (got <= 0) return "download_failed";
		have += (size_t)got;
		int status;
		uint32_t length;
		size_t head_len;
		int parsed = hat_ota_parse_http_head(job->head, have, &status, &length, &head_len);
		if (parsed < 0) return "download_failed";
		if (parsed == 0) continue;
		if (status != 200) {
			printf("\r\n[hat-ota] server answered HTTP %d\r\n", status);
			return "http_status";
		}
		if (length != job->size) return "size_mismatch";
		job->leftover_pos = head_len;
		job->leftover_len = have;
		return NULL;
	}
}

static void hat_ota_task(void *param)
{
	hat_ota_job_t *job = param;
	const char *reason = NULL;
	uint8_t *block = malloc(HAT_OTA_BLOCK_SIZE);

	printf("\r\n[hat-ota] downloading %s (%lu bytes) from %s:%u\r\n", job->version,
		   (unsigned long)job->size, job->host, job->port);
	job->fd = -1;
	if (!block) reason = "out_of_memory";
	if (!reason && (job->fd = hat_ota_connect(job)) < 0) reason = "connect_failed";
	if (!reason) reason = hat_ota_request(job);
	if (!reason) {
		hat_ota_io_t io = { job, hat_ota_read, hat_ota_flash, hat_ota_progress };
		uint32_t running = hal_sys_get_fw_timest(hal_sys_get_ld_fw_idx());
		reason = hat_ota_write_image(&io, job->size, job->sha256, running, block);
	}
	if (job->fd >= 0) close(job->fd);
	free(block);

	if (reason) {
		hat_ota_notify_error(reason);
		hat_ota_running = false;
		vTaskDelete(NULL);
		return;
	}
	char json[96];
	snprintf(json, sizeof(json), "{\"event\":\"ota\",\"status\":\"rebooting\",\"version\":\"%s\"}", job->version);
	printf("\r\n[hat-ota] image verified; rebooting into %s\r\n", job->version);
	hat_ota_notify(json);
	vTaskDelay(pdMS_TO_TICKS(HAT_OTA_REBOOT_DELAY_MS));
	ota_platform_reset();
	vTaskDelete(NULL);
}

static bool hat_ota_streaming(void)
{
	uint32_t sent_bytes;
	const char *state;
	hat_stream_stats(&sent_bytes, &state);
	return strcmp(state, "idle") != 0 && strcmp(state, "stopped") != 0;
}

const char *hat_ota_start(const char *url, uint32_t size, const uint8_t sha256[HAT_OTA_SHA256_LEN],
						  const char *version)
{
	if (hat_ota_running) return "busy";
	if (wifi_is_connected_to_ap() != RTW_SUCCESS) return "no_wifi";
	if (hat_ota_streaming()) return "streaming";
	uint8_t running_idx = hal_sys_get_ld_fw_idx();
	if (sys_get_boot_sel() != 0 || (running_idx != 1 && running_idx != 2)) return "unsupported_flash";

	hat_ota_job_t *job = &hat_ota_job;
	memset(job, 0, sizeof(*job));
	if (!hat_ota_parse_url(url, job->host, &job->port, job->path)) return "bad_url";
	if (size < HAT_OTA_MIN_IMAGE_SIZE) return "bad_size";
	snprintf(job->version, sizeof(job->version), "%s", version ? version : "unknown");
	job->size = size;
	memcpy(job->sha256, sha256, HAT_OTA_SHA256_LEN);
	job->target_fw_idx = running_idx == 1 ? OTA_FW2 : OTA_FW1;

	hat_ota_running = true;
	if (xTaskCreate(hat_ota_task, (const char *)"hat_ota", 2048, job, tskIDLE_PRIORITY + 1, NULL) != pdPASS) {
		hat_ota_running = false;
		return "out_of_memory";
	}
	return NULL;
}
