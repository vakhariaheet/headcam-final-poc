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
```

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
