# UmpireHat native firmware (AmebaPro2 RTOS SDK)

**Current source: outbound RTMP publishing, no local RTSP server.** The native
flash image builds. The same sender/client code has passed host tests against
MediaMTX, including decoded 1080p video and recovery after server restart.
This RTMP image has not yet been flashed/tested on the board. The preceding
JXF37 camera + local RTSP image was verified on hardware on 2026-09-29.

## Data path and controls

```text
JXF37 camera → H.264 encoder → bounded frame queue → outbound RTMP/TCP
                                                       ↓
                                               cloud MediaMTX
                                                       ↓ internal RTSP
                                               compositor worker
```

The hat accepts no inbound streaming connections and requires no port
forwarding or phone relay. BLE stays available for control. Pairing starts
the camera, but discards frames until an explicit `START_STREAM`. A dedicated
sender handles network I/O; the camera callback only copies to a six-frame
queue. Oversized frames or a full queue trigger resynchronization through a
new publishing connection and a fresh SPS/PPS + IDR, not a growing backlog.

- BLE advertisement: `UmpireHat_XXXX`; service `FFE0`, command `FFE1`, status `FFE2`.
- Provision: `{"cmd":"SET_STA","ssid":"...","pass":"...","band":"2.4"}`.
- Start: `{"cmd":"START_STREAM","url":"rtmp://ingest.example.com:1935/live/hat"}`.
- Stop: `{"cmd":"STOP_STREAM"}`. Stops publishing/retries, keeps camera/Wi-Fi ready.
- Omitting `url` uses `HAT_DEFAULT_RTMP_URL` from optional `cloud_config.h`.
  Its default is empty; no placeholder host is contacted.
- FFE2 stream notifications use `{"event":"stream","status":"connecting"}`,
  then `publishing`, `reconnecting`, or `stopped`. Provisioning retains
  `{"status":"connected","ip":"..."}` / `{"status":"error","reason":"..."}`.
- Start is rejected before camera readiness, with an invalid/missing URL,
  or while already requested. STOP is idempotent and cancels retries.
- `publishing` means RTMP publish was accepted and an IDR was sent; the cloud
  reader can need a short additional interval to discover its track.
- Connection failures retry at 1, 2, 4, 8, 16, then 30-second intervals while
  start remains requested. Socket waits check cancellation every 100 ms and
  have five-second I/O deadlines. DNS resolution uses the platform resolver.
- A lost Wi-Fi association is retried using only the provisioned in-memory
  credentials. SDK boot-time loading/saving of old profiles remains disabled.

The mobile Start Broadcast action now starts publishing before creating the
cloud compositor session. Failed starts attempt to stop publishing. End
Broadcast attempts both hat and cloud shutdown independently. Unexpected
cloud-session termination also attempts to stop the hat. BLE disconnection
alone does not stop publishing, so backgrounding a phone does not end a stream.
The planned cloud-composited preflight preview is a separate follow-up; this
slice starts publishing when Start Broadcast is pressed.

## Set the cloud URL later

Preferred: pass it to the app at build/run time (no firmware rebuild needed):

```bash
flutter run --dart-define=HAT_INGEST_URL=rtmp://INGEST_HOST:1935/live/hat \
  --dart-define=CLOUD_BASE_URL=http://CONTROL_HOST:4100
```

Alternatively, copy `src/mmfv2_video_example/cloud_config.example.h` to
`cloud_config.h`, set `HAT_DEFAULT_RTMP_URL`, rerun the symlink/build steps,
and omit the app define. `cloud_config.h` is gitignored. URLs must be shorter
than 384 bytes; the entire BLE JSON command must be shorter than 512 bytes.
Do not commit production stream keys or URLs containing credentials.

This initial client supports **plain RTMP over IPv4 TCP**, H.264 video only,
with no B frames. It rejects `rtmps://`; TLS is not implemented. Public cloud
ingest authentication and encryption must be configured for the actual
server, not inferred from the local POC's anonymous MediaMTX defaults. The
cloud URL must identify the same path the worker reads (`live/hat` by default).
No microphone/AAC, per-device path allocation, credential persistence,
account binding, periodic BLE telemetry, or OTA is added in this slice.

## Provisioning behavior

The worker exists before advertising. BLE waits for Wi-Fi hardware readiness
before starting the controller. Credential lengths, queue allocation, and
concurrent provisioning are checked. Wi-Fi association has a 30-second
deadline; DHCP has the SDK's separate timeout. The mobile pairing wait is 120 seconds to cover these stages, and ignores
cached values and stream-control events on the shared status characteristic.

Provisioning success requires DHCP and encoder frames. Failed Wi-Fi attempts
can be retried; an active or partially initialized camera requires reset
before another provisioning attempt. Partial SDK video state is retained for
diagnosis rather than repeatedly reinitialized. Start/stop of RTMP itself
does not require a reset or another Wi-Fi pairing.

## SDK and build setup

The external SDK is `~/Desktop/ddev/ameba-rtos-pro2`; ARM GCC 10.3.1 is under
`~/Desktop/ddev/ameba-toolchain/asdk-10.3.1/`. This repo owns the application
sources; the SDK is the build sandbox. The obsolete Arduino prototypes have been retired; this is the active firmware.

From the repository root:

```bash
SDK_PROJECT=~/Desktop/ddev/ameba-rtos-pro2/project/realtek_amebapro2_v0_example
REPO_NATIVE=$(pwd)/firmware/amb82_hat_native
ln -sf "$REPO_NATIVE/src/app_example.c" "$SDK_PROJECT/src/mmfv2_video_example/app_example.c"
for file in "$REPO_NATIVE"/src/mmfv2_video_example/*.[ch]; do
  ln -sf "$file" "$SDK_PROJECT/src/mmfv2_video_example/$(basename "$file")"
done
# This link can be dangling until you create the optional local config.
ln -sf "$REPO_NATIVE/src/mmfv2_video_example/cloud_config.h" \
  "$SDK_PROJECT/src/mmfv2_video_example/cloud_config.h"
mkdir -p "$SDK_PROJECT/src/ble_provisioning"
for file in "$REPO_NATIVE"/src/ble_provisioning/*.[ch]; do
  ln -sf "$file" "$SDK_PROJECT/src/ble_provisioning/$(basename "$file")"
done
ln -sf "$REPO_NATIVE/src/platform_opts_bt.h" "$SDK_PROJECT/inc/platform_opts_bt.h"
ln -sf "$REPO_NATIVE/src/sensor.h" "$SDK_PROJECT/inc/sensor.h"
# Create once; do not replace a real third_party directory in a different SDK.
ln -s "$REPO_NATIVE/third_party" "$SDK_PROJECT/third_party"
```

The workstation's SDK `GCC-RELEASE/application/application.cmake` already
retains `ble_peripheral/app_task.c`, replaces the stock peripheral app/service/
AT-command sources with the three `src/ble_provisioning/*.c` files, and includes
`src/ble_provisioning`, `src/mmfv2_video_example`, and `component/network/cJSON`.
These SDK CMake changes remain outside this repository. The video directory
uses a non-recursive C-source glob; rerun CMake when adding files.

```bash
cd ~/Desktop/ddev/ameba-rtos-pro2/project/realtek_amebapro2_v0_example/GCC-RELEASE
export PATH="$HOME/Desktop/ddev/ameba-toolchain/asdk-10.3.1/darwin/newlib/bin:$PATH"
cmake -S . -B build -G "Unix Makefiles" -DVIDEO_EXAMPLE=ON
# Required after changing sensor.h; the vendor rule omits this dependency.
rm -f build/application/firmware_isp_iq.bin build/application/isp_iq.bin
cmake --build build --target flash -j4
```

`--target flash` packages the image. A default build alone can leave an old
`flash_ntz.bin`. To flash, enter download mode (hold UART_DOWNLOAD, press and
release RESET, release UART_DOWNLOAD), then:

```bash
~/Desktop/ddev/ameba-rtos-pro2/tools/Pro2_PG_tool_v1.4.3/uartfwburn.arm.darwin \
  -p /dev/cu.wchusbserial<N> -f build/flash_ntz.bin -b 3000000 -U
```

Press RESET once to boot. Serial baud is 115200. Confirm
`Camera ready; cloud publisher idle (no local RTSP server)`, then explicitly
start publishing from the updated app. Verify MediaMTX reports the publisher,
read/decode its stream on the server, STOP, and confirm the publisher goes
away while BLE/Wi-Fi remain available. Also verify hat port 554 is closed.
These board-level RTMP checks and a real external cloud test remain pending.

## Tests and dependencies

See [tests/README.md](tests/README.md) for host unit/integration commands.
The host sender harness runs the actual publisher module with pthread-backed
RTOS shims; it tests invalid/duplicate starts, STOP during a stalled handshake,
STOP during retry backoff, video decoding, server restart/recovery, and restart
after STOP. It does not replace a board/lwIP performance or endurance test.

The RTMP protocol implementation is vendored, pinned librtmp; see
[third_party/librtmp/README.md](third_party/librtmp/README.md) and its retained
LGPL license/source notices. Our code supplies lwIP/cancellable socket adapters,
H.264 Annex-B to AVC packetization, frame ownership, and the publisher lifecycle.
MediaMTX protocol/configuration references:
[RTMP publishing](https://mediamtx.org/docs/features/publish),
[configuration](https://mediamtx.org/docs/references/configuration-file).

## Outbound build checkpoint (2026-09-29)

- Native `flash` target: successful; source files match the packaged image.
- H.264 packetizer: AddressSanitizer/UndefinedBehaviorSanitizer tests passed.
- Actual sender module with host RTOS shims: integration passed with sanitizers,
  including decoded video before/after ingest restart and cancellation cases.
- Mobile: full 50-test suite passed; focused pairing/control checks passed
  after status-notification filtering changes; analyzer reports no issues.
- Cloud worker: TypeScript build and lint passed; Compose configuration validates.
- Outbound image SHA-256:
  `7c00bf4dba142bbf79a79e104245b3ce3dd19b96394da26bc1208673458dbcc4`.
- Not yet flashed; board/lwIP streaming and the real external endpoint remain
  unverified. The endpoint can be set later with `HAT_INGEST_URL`.

Temporary workstation logs: `/tmp/hat-rtmp-build.log`,
`/tmp/hat-sender-asan.log`, `/tmp/hat-mobile-final-tests.log`,
`/tmp/hat-mobile-last-tests.log`, `/tmp/hat-mobile-analyze.log`.

## Earlier board checkpoint: JXF37 camera (2026-09-29)

The SDK originally selected GC2053 and packaged no F37 sensor. That native
image joined Wi-Fi but failed camera startup with `VOE command 0x206 fail`.
The tracked `sensor.h` selects JXF37 and packages dummy + F37 sensor/IQ entries.
Regenerating and flashing that package resolved the zero-frame failure: BLE
provisioning/DHCP succeeded and FFmpeg decoded 300 frames of 1080p30 H.264 from
the earlier local RTSP image. A `hal_voe_send2voe too long` diagnostic still
appeared on successful startup; actual frames established camera health.

That earlier image's SHA-256 was
`1130bb9cbbba3fd2e3a622cd5724c5483af4f896f5022d434aae7b4b7d65d4a6`.
It is the last board-verified image, not the new outbound-RTMP build.
