// Host tests for the firmware update core: the SHA-256 gate on the final
// (activating) block, timestamp and download failures, URL and HTTP parsing.
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hat_ota_image.h"
#include "mbedtls/sha256.h"

#define SLOT_SIZE (8 * HAT_OTA_BLOCK_SIZE)

typedef struct {
    const uint8_t *image;
    size_t size;
    size_t pos;
    size_t chunk;      // bytes per read(), to exercise partial reads
    size_t fail_at;    // read() fails once pos reaches this
    uint8_t slot[SLOT_SIZE];
    uint32_t blocks_written;
    uint32_t total_blocks;
    bool activated;    // final block written (the SDK writes the boot label then)
    uint8_t checksum[4];
    int fail_flash_block;
    uint8_t last_progress;
} fake_t;

static int fake_read(void *context, uint8_t *buf, size_t len) {
    fake_t *f = context;
    if (f->pos >= f->fail_at || f->pos >= f->size) return 0;
    size_t n = len < f->chunk ? len : f->chunk;
    if (n > f->size - f->pos) n = f->size - f->pos;
    if (n > f->fail_at - f->pos) n = f->fail_at - f->pos;
    memcpy(buf, f->image + f->pos, n);
    f->pos += n;
    return (int)n;
}

static int fake_flash(void *context, uint32_t total_blocks, uint32_t block, uint8_t *buf, uint32_t len,
                      const uint8_t checksum[4]) {
    fake_t *f = context;
    if ((int)block == f->fail_flash_block) return -1;
    assert(block == f->blocks_written); // in order, no gaps
    assert(len <= HAT_OTA_BLOCK_SIZE);
    memcpy(f->slot + block * HAT_OTA_BLOCK_SIZE, buf, len);
    f->blocks_written++;
    f->total_blocks = total_blocks;
    if (block == total_blocks - 1) {
        f->activated = true;
        memcpy(f->checksum, checksum, 4);
        for (uint32_t i = len; i < HAT_OTA_BLOCK_SIZE; i++) assert(buf[i] == 0xFF); // padded
    }
    return 0;
}

static void fake_progress(void *context, uint8_t percent) {
    fake_t *f = context;
    assert(percent >= f->last_progress && percent <= 100);
    f->last_progress = percent;
}

static uint8_t *make_image(size_t size, uint32_t timestamp, uint8_t sha[32]) {
    uint8_t *image = malloc(size);
    for (size_t i = 0; i < size; i++) image[i] = (uint8_t)(i * 31 + 7);
    image[HAT_OTA_TIMESTAMP_OFFSET + 0] = (uint8_t)timestamp;
    image[HAT_OTA_TIMESTAMP_OFFSET + 1] = (uint8_t)(timestamp >> 8);
    image[HAT_OTA_TIMESTAMP_OFFSET + 2] = (uint8_t)(timestamp >> 16);
    image[HAT_OTA_TIMESTAMP_OFFSET + 3] = (uint8_t)(timestamp >> 24);
    assert(mbedtls_sha256_ret(image, size, sha, 0) == 0);
    return image;
}

static const char *run(fake_t *f, uint32_t size, const uint8_t sha[32], uint32_t running) {
    static uint8_t block[HAT_OTA_BLOCK_SIZE];
    hat_ota_io_t io = { f, fake_read, fake_flash, fake_progress };
    return hat_ota_write_image(&io, size, sha, running, block);
}

static fake_t fake(const uint8_t *image, size_t size) {
    fake_t f;
    memset(&f, 0, sizeof(f));
    f.image = image; f.size = size; f.chunk = 1000; f.fail_at = (size_t)-1; f.fail_flash_block = -1;
    return f;
}

static void test_image_writes(void) {
    uint8_t sha[32];
    const size_t size = 3 * HAT_OTA_BLOCK_SIZE + 100 + 4;
    uint8_t *image = make_image(size, 0x5000, sha);

    // Success: every firmware byte lands in order, checksum handed over last.
    fake_t f = fake(image, size);
    assert(run(&f, size, sha, 0x4000) == NULL);
    assert(f.activated && f.blocks_written == 4 && f.total_blocks == 4 && f.last_progress == 100);
    assert(memcmp(f.slot, image, size - 4) == 0);
    assert(memcmp(f.checksum, image + size - 4, 4) == 0);

    // Re-flashing the same build (equal timestamp) is allowed.
    f = fake(image, size);
    assert(run(&f, size, sha, 0x5000) == NULL && f.activated);

    // Wrong hash: earlier blocks may land in the inactive slot, but the
    // activating final block never does.
    uint8_t wrong[32]; memcpy(wrong, sha, 32); wrong[0] ^= 1;
    f = fake(image, size);
    assert(strcmp(run(&f, size, wrong, 0), "hash_mismatch") == 0);
    assert(!f.activated && f.blocks_written == 3);

    // A tampered byte anywhere, including the trailing checksum, is caught.
    for (size_t at = 0; at < size; at += size / 7) {
        uint8_t *tampered = malloc(size); memcpy(tampered, image, size);
        tampered[at == 0 ? HAT_OTA_TIMESTAMP_OFFSET + 8 : at] ^= 0x40;
        f = fake(tampered, size);
        assert(strcmp(run(&f, size, sha, 0), "hash_mismatch") == 0 && !f.activated);
        free(tampered);
    }
    uint8_t *tail = malloc(size); memcpy(tail, image, size); tail[size - 1] ^= 1;
    f = fake(tail, size);
    assert(strcmp(run(&f, size, sha, 0), "hash_mismatch") == 0 && !f.activated);
    free(tail);

    // Older builds are refused before anything is erased.
    f = fake(image, size);
    assert(strcmp(run(&f, size, sha, 0x5001), "older_firmware") == 0 && f.blocks_written == 0);

    // Connection drops, mid-image and inside the trailing checksum.
    f = fake(image, size); f.fail_at = HAT_OTA_BLOCK_SIZE + 10;
    assert(strcmp(run(&f, size, sha, 0), "download_failed") == 0 && !f.activated);
    f = fake(image, size); f.fail_at = size - 2;
    assert(strcmp(run(&f, size, sha, 0), "download_failed") == 0 && !f.activated);

    // Flash errors stop the update.
    f = fake(image, size); f.fail_flash_block = 1;
    assert(strcmp(run(&f, size, sha, 0), "flash_failed") == 0 && !f.activated);
    f = fake(image, size); f.fail_flash_block = 3;
    assert(strcmp(run(&f, size, sha, 0), "flash_failed") == 0 && !f.activated);

    // One byte per read still works.
    f = fake(image, size); f.chunk = 1;
    assert(run(&f, size, sha, 0) == NULL && f.activated);
    free(image);

    // Firmware an exact number of blocks long (like the real build): no
    // empty trailing block.
    const size_t even = 2 * HAT_OTA_BLOCK_SIZE + 4;
    image = make_image(even, 1, sha);
    f = fake(image, even);
    assert(run(&f, even, sha, 0) == NULL && f.total_blocks == 2 && f.blocks_written == 2);
    free(image);

    // Too small to hold the manifest timestamp.
    f = fake(NULL, 0);
    assert(strcmp(run(&f, HAT_OTA_MIN_IMAGE_SIZE - 1, sha, 0), "bad_size") == 0);
}

static void test_urls(void) {
    char host[HAT_OTA_HOST_MAX], path[HAT_OTA_PATH_MAX];
    uint16_t port;
    assert(hat_ota_parse_url("http://192.168.1.20:4000/api/v1/firmware/0.3.0/ota.bin", host, &port, path));
    assert(strcmp(host, "192.168.1.20") == 0 && port == 4000 && strcmp(path, "/api/v1/firmware/0.3.0/ota.bin") == 0);
    assert(hat_ota_parse_url("http://example.com/ota.bin", host, &port, path) && port == 80);
    assert(strcmp(host, "example.com") == 0 && strcmp(path, "/ota.bin") == 0);

    assert(!hat_ota_parse_url("https://example.com/ota.bin", host, &port, path)); // TLS unsupported
    assert(!hat_ota_parse_url("http://example.com", host, &port, path));          // no path
    assert(!hat_ota_parse_url("http:///ota.bin", host, &port, path));             // no host
    assert(!hat_ota_parse_url("http://example.com:/ota.bin", host, &port, path));
    assert(!hat_ota_parse_url("http://example.com:0/ota.bin", host, &port, path));
    assert(!hat_ota_parse_url("http://example.com:65536/ota.bin", host, &port, path));
    assert(!hat_ota_parse_url("http://example.com:8x/ota.bin", host, &port, path));
    assert(!hat_ota_parse_url("http://user@example.com/ota.bin", host, &port, path));
    assert(!hat_ota_parse_url("http://example.com/ota bin", host, &port, path));
    assert(!hat_ota_parse_url("http://example.com/x\r\nHost: evil", host, &port, path));
    assert(!hat_ota_parse_url(NULL, host, &port, path));

    char long_url[400] = "http://example.com/";
    memset(long_url + strlen(long_url), 'a', 250);
    assert(!hat_ota_parse_url(long_url, host, &port, path));
}

static int head(const char *text, int *status, uint32_t *length, size_t *head_len) {
    return hat_ota_parse_http_head(text, strlen(text), status, length, head_len);
}

static void test_http_heads(void) {
    int status; uint32_t length; size_t head_len;
    const char *ok = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
                     "content-length:  3088388 \r\n\r\nBODY";
    assert(head(ok, &status, &length, &head_len) == 1);
    assert(status == 200 && length == 3088388 && strcmp(ok + head_len, "BODY") == 0);

    // Incomplete heads ask for more, at every split point.
    for (size_t cut = 0; cut < strlen(ok) - 4; cut++) {
        assert(hat_ota_parse_http_head(ok, cut, &status, &length, &head_len) == 0);
    }

    assert(head("HTTP/1.0 404 Not Found\r\nContent-Length: 9\r\n\r\n", &status, &length, &head_len) == 1);
    assert(status == 404);
    assert(head("HTTP/1.1 200 OK\r\n\r\n", &status, &length, &head_len) == -1);      // no length
    assert(head("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 4\r\n\r\n",
                &status, &length, &head_len) == -1);
    assert(head("HTTP/1.1 200 OK\r\nContent-Length: 12a\r\n\r\n", &status, &length, &head_len) == -1);
    assert(head("HTTP/1.1 200 OK\r\nContent-Length: 99999999999\r\n\r\n", &status, &length, &head_len) == -1);
    assert(head("HTTP/1.1 200 OK\r\nContent-Length: 4\r\nContent-Length: 5\r\n\r\n",
                &status, &length, &head_len) == -1);
    assert(head("SSH-2.0-x\r\n\r\n", &status, &length, &head_len) == -1);
    // Header names must match whole, not by prefix.
    assert(head("HTTP/1.1 200 OK\r\nContent-Length-X: 4\r\n\r\n", &status, &length, &head_len) == -1);
}

int main(void) {
    test_image_writes();
    test_urls();
    test_http_heads();
    printf("ota image tests passed\n");
    return 0;
}
