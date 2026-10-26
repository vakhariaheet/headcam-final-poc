#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Firmware update core, independent of the SDK so host tests can run it.
//
// The image is the build's ota.bin: firmware.bin followed by a 4-byte
// additive checksum that the SDK's ota_flash_NOR() checks against flash.
// It is written block by block into the inactive firmware slot. The SDK
// withholds the slot's 8-byte boot label until the final block, so the
// bootloader ignores the slot until then. This code withholds the final
// block itself until the whole image matches the SHA-256 the owner sent over
// the encrypted BLE channel. A failed, tampered, or interrupted download
// therefore never becomes bootable, and the running slot is never touched.

#define HAT_OTA_BLOCK_SIZE 4096
#define HAT_OTA_SHA256_LEN 32
#define HAT_OTA_TIMESTAMP_OFFSET 0x2D4 // manifest TIMST, as read by the SDK's heap_update_ota()
#define HAT_OTA_MIN_IMAGE_SIZE (HAT_OTA_TIMESTAMP_OFFSET + 4 + 4)
#define HAT_OTA_HOST_MAX 64
#define HAT_OTA_PATH_MAX 192

typedef struct {
	void *context;
	// Reads up to len bytes; returns the count, or <= 0 on error or EOF.
	int (*read)(void *context, uint8_t *buf, size_t len);
	// Writes one block (ota_flash_NOR semantics: may modify buf). checksum is
	// the image's trailing checksum, meaningful only for the final block.
	// Returns 0 on success.
	int (*flash)(void *context, uint32_t total_blocks, uint32_t block, uint8_t *buf, uint32_t len,
				 const uint8_t checksum[4]);
	// Called with 0-100 as blocks are written; may be NULL.
	void (*progress)(void *context, uint8_t percent);
} hat_ota_io_t;

// Streams image_size bytes from io into flash. Refuses images built before
// running_timestamp (the bootloader would never pick them). block must hold
// HAT_OTA_BLOCK_SIZE bytes. Returns NULL once the final block is written, or
// a short reason: bad_size, download_failed, older_firmware, hash_mismatch,
// flash_failed.
const char *hat_ota_write_image(const hat_ota_io_t *io, uint32_t image_size,
								const uint8_t expected_sha256[HAT_OTA_SHA256_LEN],
								uint32_t running_timestamp, uint8_t *block);

// Splits http://host[:port]/path. Only plain HTTP: the image's integrity
// comes from the SHA-256, not the transport.
bool hat_ota_parse_url(const char *url, char host[HAT_OTA_HOST_MAX], uint16_t *port,
					   char path[HAT_OTA_PATH_MAX]);

// Parses an HTTP/1.x response head in buf[0..len). Returns 1 with the status,
// Content-Length, and head length once the blank line has arrived; 0 when more
// bytes are needed; -1 if malformed, chunked, or missing Content-Length.
int hat_ota_parse_http_head(const char *buf, size_t len, int *status, uint32_t *content_length,
							size_t *head_len);
