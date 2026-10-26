# Native firmware host tests

Run from the repository root with a C compiler, FFmpeg, Python 3, and Docker.
No board or real Wi-Fi credentials are required.

```bash
HAT_SRC=firmware/amb82_hat_native/src/mmfv2_video_example
HAT_TEST=firmware/amb82_hat_native/tests
cc -std=c99 -Wall -Wextra -Werror -I"$HAT_TEST/stubs" -I"$HAT_SRC" \
  "$HAT_TEST/provisioning_test.c" -o /tmp/hat-provisioning-test
/tmp/hat-provisioning-test
cc -std=c99 -Wall -Wextra -Werror -fsanitize=address,undefined -I"$HAT_SRC" \
  "$HAT_TEST/h264_test.c" "$HAT_SRC/hat_h264.c" -o /tmp/hat-h264-test
/tmp/hat-h264-test
cc -std=gnu99 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -I"$HAT_TEST/stubs" -I"$HAT_SRC" \
  "$HAT_TEST/wifi_store_test.c" -o /tmp/hat-wifi-store-test
/tmp/hat-wifi-store-test
cc -std=c99 -Wall -Wextra -Werror -fsanitize=address,undefined -I"$HAT_SRC" \
  "$HAT_TEST/led_pattern_test.c" -o /tmp/hat-led-pattern-test
/tmp/hat-led-pattern-test
cc -std=c99 -Wall -Wextra -Werror -fsanitize=address,undefined -I"$HAT_SRC" \
  "$HAT_TEST/press_test.c" -o /tmp/hat-press-test
/tmp/hat-press-test
# macOS: uses CommonCrypto for real HMAC-SHA256.
cc -std=gnu99 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -I"$HAT_TEST/stubs" -I"$HAT_SRC" \
  "$HAT_TEST/pairing_test.c" -o /tmp/hat-pairing-test
/tmp/hat-pairing-test
cc -std=gnu99 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -I"$HAT_TEST/stubs" -I"$HAT_SRC" \
  "$HAT_TEST/camera_guard_test.c" -o /tmp/hat-camera-guard-test
/tmp/hat-camera-guard-test
```

`camera_guard_test.c` simulates reboots against an in-memory FTL: three
restarts then giving up, a power cycle after giving up starting a fresh
streak, a power cycle mid-streak keeping the count, healthy runs ending a
streak (without a write when there is none), an unsaveable streak stopping
instead of rebooting, and corrupt records.

The secure-channel test compiles the firmware's `hat_crypto.c` and
`hat_secure.c` against the SDK's own mbedTLS 2.28 sources, using a minimal
host configuration in `host_mbedtls/` instead of the SDK's hardware ALT code:

```bash
M=~/Desktop/ddev/ameba-rtos-pro2/component/ssl/mbedtls-2.28.1
cc -std=gnu99 -fsanitize=address,undefined \
  -DMBEDTLS_CONFIG_FILE='"host_mbedtls_config.h"' \
  -I"$HAT_TEST/host_mbedtls" -I"$M/include" -I"$HAT_SRC" \
  "$HAT_TEST/secure_test.c" "$HAT_SRC/hat_secure.c" "$HAT_SRC/hat_crypto.c" \
  $M/library/{aes,bignum,cipher,cipher_wrap,constant_time,ecdh,ecp,ecp_curves,gcm,md,platform_util,sha256}.c \
  -o /tmp/hat-secure-test
/tmp/hat-secure-test             # add --vectors to print cross-check values
```

The firmware update core uses the same host mbedTLS build:

```bash
cc -std=gnu99 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -DMBEDTLS_CONFIG_FILE='"host_mbedtls_config.h"' \
  -I"$HAT_TEST/host_mbedtls" -I"$M/include" -I"$HAT_SRC" \
  "$HAT_TEST/ota_image_test.c" "$HAT_SRC/hat_ota_image.c" \
  $M/library/{sha256,platform_util}.c -o /tmp/hat-ota-image-test
/tmp/hat-ota-image-test
```

`ota_image_test.c` checks that the final (activating) block is never written
unless the whole image matches the SHA-256: wrong hash, a tampered byte
anywhere including the trailing checksum, and truncation mid-image or inside
the checksum all leave the slot unbootable. It also covers refusing older
builds before erasing anything, flash errors, one-byte reads, an image an
exact number of blocks long, URL parsing (HTTP only, no userinfo, no request
splitting), and HTTP response heads (split at every byte, case-insensitive
Content-Length, chunked and missing lengths refused).

The secure-channel test covers base64, the RFC 5869 HKDF vector, claim key agreement (both sides
derive the same owner key), off-curve and malformed key rejection, and sealed
SET_STA round trips that fail on the wrong command, wrong key, tampering, or
truncation. `--vectors` prints fixed-seed values that
`mobile/test/hat_ownership_test.dart` checks, proving the app derives the
same keys and ciphertext byte-for-byte. Regenerate both together if the
protocol changes.

`press_test.c` covers button gestures: short/pairing/reset thresholds, the
ignored 1–3 s band, debounce, hold-stage feedback, a button held at boot,
and clock wraparound. `pairing_test.c` covers the pairing window and its
expiry, the 30 s authentication deadline (paused while pairing is open),
claiming, owner-key persistence, single-use challenges, wrong-key/tampered
MAC/wrong-nonce rejection, owner replacement, RNG failure, and clearing.

`provisioning_test.c` also covers the boot-time saved-network reconnect:
retry backoff, an app `SET_STA` superseding a pending retry, and stopping
retries once the camera has failed. `wifi_store_test.c` runs the credential
record against an in-memory FTL: erased flash, round trip, unchanged-write
skipping, maximum lengths, corruption detection, clearing, and I/O failure.
Network switching and BLE telemetry depend on the vendor Wi-Fi/BLE stacks and
still need board tests.

The integration harness compiles the real MMF sink/sender against small
pthread RTOS shims and streams generated Annex-B access units into it.
MediaMTX is isolated from the application's existing containers. Ports are
bound only to loopback. The test restarts **only** `hat-rtmp-test`.

```bash
cc -std=gnu99 -D_DARWIN_C_SOURCE -pthread -fsanitize=address,undefined \
  -I"$HAT_TEST/sender_stubs" -I"$HAT_SRC" \
  "$HAT_TEST/sender_harness.c" "$HAT_TEST/sender_host_os.c" \
  "$HAT_SRC/module_hat_rtmp.c" "$HAT_SRC/hat_h264.c" \
  "$HAT_SRC/hat_rtmp_client.c" "$HAT_SRC/hat_rtmp_transport.c" \
  "$HAT_SRC"/librtmp_*.c -o /tmp/hat-sender-harness
ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 \
  -t 20 -c:v libx264 -preset ultrafast -b:v 2M -g 30 -bf 0 \
  -x264-params aud=1:repeat-headers=1 -f h264 -y /tmp/hat-rtmp-test.h264
docker run -d --rm --name hat-rtmp-test \
  -p 127.0.0.1:19350:1935 -p 127.0.0.1:18554:8554 \
  bluenviron/mediamtx:1.21.1
python3 "$HAT_TEST/sender_integration.py" \
  /tmp/hat-sender-harness /tmp/hat-rtmp-test.h264
docker stop hat-rtmp-test
```

Passing output includes decoded 1080p video both before and after the server
restart. Cancellation during a stalled handshake and retry backoff must
complete within two seconds. This exercises TCP/RTMP and actual sender logic;
BLE, lwIP, encoder backpressure, and real Wi-Fi recovery still need board tests.

`rtmp_publish.c` is a smaller single-session host driver useful for testing a
provided ingest endpoint. It uses the same client/packetizer and accepts an
RTMP URL plus an AUD-delimited `.h264` file. Avoid putting private URLs in shell
history or committed test fixtures.

## Queue overflow regression checks

These tests deterministically stall a send and fill the actual sender queue,
then assert recovery uses the same connection and STOP still closes it.
A packet-capture test checks that dependent frames are skipped and the resumed
IDR/sequence header retain the original timestamp origin.

```bash
cc -std=gnu99 -D_DARWIN_C_SOURCE -pthread -fsanitize=address,undefined \
  -I"$HAT_TEST/sender_stubs" -I"$HAT_SRC" \
  "$HAT_TEST/sender_overflow_test.c" "$HAT_TEST/sender_host_os.c" \
  "$HAT_SRC/module_hat_rtmp.c" "$HAT_SRC/hat_rtmp_transport.c" \
  -o /tmp/hat-overflow-test
/tmp/hat-overflow-test
cc -std=gnu99 -D_DARWIN_C_SOURCE -fsanitize=address,undefined -I"$HAT_SRC" \
  "$HAT_TEST/client_resync_test.c" "$HAT_SRC/hat_h264.c" \
  "$HAT_SRC/hat_rtmp_transport.c" "$HAT_SRC"/librtmp_*.c \
  -o /tmp/hat-client-resync-test
/tmp/hat-client-resync-test
```
