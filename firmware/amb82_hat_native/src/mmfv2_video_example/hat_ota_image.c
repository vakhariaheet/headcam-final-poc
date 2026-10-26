// SDK-independent firmware update core; see hat_ota_image.h.

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "mbedtls/sha256.h"

#include "hat_ota_image.h"

static bool hat_ota_read_full(const hat_ota_io_t *io, uint8_t *buf, size_t len)
{
	size_t done = 0;
	while (done < len) {
		int got = io->read(io->context, buf + done, len - done);
		if (got <= 0) return false;
		done += (size_t)got;
	}
	return true;
}

static uint32_t hat_ota_read_le32(const uint8_t *bytes)
{
	return (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 | (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
}

const char *hat_ota_write_image(const hat_ota_io_t *io, uint32_t image_size,
								const uint8_t expected_sha256[HAT_OTA_SHA256_LEN],
								uint32_t running_timestamp, uint8_t *block)
{
	if (image_size < HAT_OTA_MIN_IMAGE_SIZE) return "bad_size";
	uint32_t firmware_len = image_size - 4;
	uint32_t total_blocks = (firmware_len + HAT_OTA_BLOCK_SIZE - 1) / HAT_OTA_BLOCK_SIZE;
	uint8_t checksum[4] = { 0 };
	const char *reason = NULL;

	mbedtls_sha256_context sha;
	mbedtls_sha256_init(&sha);
	if (mbedtls_sha256_starts_ret(&sha, 0) != 0) reason = "hash_mismatch";

	for (uint32_t index = 0; !reason && index < total_blocks; index++) {
		uint32_t offset = index * HAT_OTA_BLOCK_SIZE;
		uint32_t len = firmware_len - offset < HAT_OTA_BLOCK_SIZE ? firmware_len - offset : HAT_OTA_BLOCK_SIZE;
		bool last = index == total_blocks - 1;

		if (!hat_ota_read_full(io, block, len)) {
			reason = "download_failed";
			break;
		}
		if (mbedtls_sha256_update_ret(&sha, block, len) != 0) {
			reason = "hash_mismatch";
			break;
		}
		// Checked before anything is erased.
		if (index == 0 && hat_ota_read_le32(block + HAT_OTA_TIMESTAMP_OFFSET) < running_timestamp) {
			reason = "older_firmware";
			break;
		}
		if (last) {
			// The final block activates the slot: verify the whole image first.
			uint8_t digest[HAT_OTA_SHA256_LEN];
			if (!hat_ota_read_full(io, checksum, sizeof(checksum))) {
				reason = "download_failed";
				break;
			}
			if (mbedtls_sha256_update_ret(&sha, checksum, sizeof(checksum)) != 0 ||
				mbedtls_sha256_finish_ret(&sha, digest) != 0 ||
				memcmp(digest, expected_sha256, sizeof(digest)) != 0) {
				reason = "hash_mismatch";
				break;
			}
			memset(block + len, 0xFF, HAT_OTA_BLOCK_SIZE - len);
		}
		if (io->flash(io->context, total_blocks, index, block, len, checksum) != 0) {
			reason = "flash_failed";
			break;
		}
		if (io->progress) io->progress(io->context, (uint8_t)((index + 1) * 100u / total_blocks));
	}
	mbedtls_sha256_free(&sha);
	return reason;
}

bool hat_ota_parse_url(const char *url, char host[HAT_OTA_HOST_MAX], uint16_t *port,
					   char path[HAT_OTA_PATH_MAX])
{
	static const char scheme[] = "http://";
	if (!url || strncmp(url, scheme, sizeof(scheme) - 1) != 0) return false;
	const char *authority = url + sizeof(scheme) - 1;
	const char *slash = strchr(authority, '/');
	if (!slash || strlen(slash) >= HAT_OTA_PATH_MAX) return false;
	const char *colon = memchr(authority, ':', (size_t)(slash - authority));
	const char *host_end = colon ? colon : slash;
	size_t host_len = (size_t)(host_end - authority);
	if (host_len == 0 || host_len >= HAT_OTA_HOST_MAX || memchr(authority, '@', host_len)) return false;

	unsigned long number = 80;
	if (colon) {
		if (colon + 1 == slash) return false;
		number = 0;
		for (const char *c = colon + 1; c < slash; c++) {
			if (!isdigit((unsigned char)*c)) return false;
			number = number * 10 + (unsigned long)(*c - '0');
			if (number > 65535) return false;
		}
		if (number == 0) return false;
	}
	for (const char *c = slash; *c; c++) {
		// Keep the request line well-formed.
		if ((unsigned char)*c <= ' ' || *c == 0x7F) return false;
	}
	memcpy(host, authority, host_len);
	host[host_len] = '\0';
	*port = (uint16_t)number;
	strcpy(path, slash);
	return true;
}

static bool hat_ota_header_is(const char *line, size_t len, const char *name)
{
	size_t name_len = strlen(name);
	if (len <= name_len || line[name_len] != ':') return false;
	for (size_t i = 0; i < name_len; i++) {
		if (tolower((unsigned char)line[i]) != name[i]) return false;
	}
	return true;
}

static const char *hat_ota_header_value(const char *line, size_t len, size_t name_len, size_t *value_len)
{
	const char *value = line + name_len + 1;
	const char *end = line + len;
	while (value < end && (*value == ' ' || *value == '\t')) value++;
	while (end > value && (end[-1] == ' ' || end[-1] == '\t')) end--;
	*value_len = (size_t)(end - value);
	return value;
}

// First CRLF at or after from, searching no further than limit.
static const char *hat_ota_crlf(const char *from, const char *limit)
{
	for (const char *c = from; c + 1 < limit; c++) {
		if (c[0] == '\r' && c[1] == '\n') return c;
	}
	return limit;
}

int hat_ota_parse_http_head(const char *buf, size_t len, int *status, uint32_t *content_length,
							size_t *head_len)
{
	const char *end = NULL;
	for (size_t i = 0; i + 3 < len; i++) {
		if (memcmp(buf + i, "\r\n\r\n", 4) == 0) {
			end = buf + i;
			break;
		}
	}
	if (!end) return 0;

	// Status line: HTTP/1.x NNN ...
	if (end - buf < 12 || memcmp(buf, "HTTP/1.", 7) != 0 || buf[8] != ' ' ||
		!isdigit((unsigned char)buf[9]) || !isdigit((unsigned char)buf[10]) || !isdigit((unsigned char)buf[11])) {
		return -1;
	}
	*status = (buf[9] - '0') * 100 + (buf[10] - '0') * 10 + (buf[11] - '0');

	bool have_length = false;
	// end points at the final header's CRLF; limit includes it.
	const char *limit = end + 2;
	const char *line = hat_ota_crlf(buf, limit) + 2;
	while (line < limit) {
		const char *line_end = hat_ota_crlf(line, limit);
		size_t line_len = (size_t)(line_end - line);
		size_t value_len;
		if (hat_ota_header_is(line, line_len, "content-length")) {
			const char *value = hat_ota_header_value(line, line_len, strlen("content-length"), &value_len);
			uint64_t number = 0;
			if (value_len == 0 || value_len > 10) return -1;
			for (size_t i = 0; i < value_len; i++) {
				if (!isdigit((unsigned char)value[i])) return -1;
				number = number * 10 + (uint64_t)(value[i] - '0');
			}
			if (number > UINT32_MAX || (have_length && number != *content_length)) return -1;
			*content_length = (uint32_t)number;
			have_length = true;
		} else if (hat_ota_header_is(line, line_len, "transfer-encoding")) {
			return -1; // chunked bodies are not supported; the server must send a length
		}
		line = line_end + 2;
	}
	if (!have_length) return -1;
	*head_len = (size_t)(end - buf) + 4;
	return 1;
}
