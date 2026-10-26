# UmpireHat native firmware (AmebaPro2 RTOS SDK)

**Current source: outbound RTMP publishing, no local RTSP server.** The native
flash image builds. The same sender/client code has passed host tests against
MediaMTX, including decoded 1080p video and recovery after server restart.
An RTMP image with the deployed ingest default was flashed on 2026-09-30;
boot and board-to-cloud streaming validation remain pending. The preceding
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
queue. Oversized frames, allocation failures, or a full queue discard the affected
queue and resume at a fresh SPS/PPS + IDR on the same RTMP connection.
Network failures still reconnect; temporary frame loss does not disconnect readers.

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
No microphone/AAC, per-device path allocation, account binding, or OTA exists yet.

## Pairing mode and ownership

The hat has **one owner**: the phone holding its owner key. A phone can only
become the owner while the hat is in **pairing mode**, which requires physical
access, as with most consumer IoT devices.

- **Pairing mode opens** automatically at boot when the hat has no owner, or
  when the button is held for 3 s. It closes after 10 minutes, on a short
  press, or when a phone claims the hat.
- **Claim (key agreement):** in pairing mode the app sends
  `{"cmd":"CLAIM","pub":"<base64 P-256 public key>"}`. The hat generates its
  own ephemeral key pair, runs ECDH, and replies
  `{"event":"claim","status":"ok","pub":"<base64>"}`. Both sides derive
  `owner_key = HKDF-SHA256(salt "umpirehat-claim-v1", ECDH shared X,
  info app_pub || hat_pub)`. **The owner key never crosses the air.** The hat
  saves it to FTL (offset 128, after the Wi-Fi record) and closes pairing
  mode. A new claim replaces the previous owner. Outside pairing mode the
  reply is `reason: pairing_closed`; an invalid or off-curve key gets
  `bad_request`.
- **Authenticate:** every link, including the one that just claimed, sends
  `{"cmd":"AUTH_START"}`, gets `{"event":"auth","nonce":"<32 hex>"}`, and
  answers `{"cmd":"AUTH","mac":"<hex HMAC-SHA256(owner key, nonce)>"}`. The
  hat replies `{"event":"auth","status":"ok"}`, or `error` with `not_owner`,
  `no_owner`, `no_challenge`, or `bad_request`. Each nonce is single-use.
  Both sides then derive `session_key = HKDF-SHA256(salt
  "umpirehat-session-v1", owner_key, info nonce)`, unique per connection.
- **Sealed parameters:** secrets travel as
  `{"cmd":"SET_STA","sealed":"<base64 iv(12) || AES-256-GCM ciphertext || tag(16)>"}`
  under the session key, with the command name as associated data (a sealed
  SET_STA cannot be replayed as another command or on another connection).
  `SET_STA` (`{"ssid","pass","band"}`) is only accepted sealed. `START_STREAM`
  with a URL must seal `{"url":...}`, since URLs can embed stream keys; a
  plaintext `url` is refused. Bare `START_STREAM`, `STOP_STREAM`, and
  `CLEAR_STA` carry no secrets.
- **Everything except CLAIM/AUTH** needs an authenticated link; otherwise the
  write fails with ATT application error `0x81`. Telemetry and status
  notifications go only to the owner, and an unauthenticated FFE2 read
  returns `{"status":"locked"}`.
- **Squatter protection:** the hat accepts one BLE link at a time. Outside
  pairing mode, a link that has not authenticated within 30 s is disconnected
  so it cannot block the owner's phone.
- **Advertising:** the scan response carries service data for the 128-bit
  UUID `AA8AEB53-18B8-4DF7-9C9B-4C579D9A9576` with one flag byte: `0x01`
  pairing mode, `0x02` has owner. No Bluetooth SIG company ID is needed.

What this protects against, and what it does not:

- A **passive** sniffer, at any time, learns neither the owner key, Wi-Fi
  credentials, nor sealed stream URLs.
- An **active** attacker who intercepts the claim itself (a live
  man-in-the-middle during the 10-minute pairing window, while the owner is
  pairing) could establish their own key, the same exposure as BLE "Just
  Works" pairing. Closing that needs an out-of-band check, such as a code
  printed on the hat or shown by its LEDs and confirmed in the app.
- An attacker with active BLE tooling could still hijack an established
  link's unsealed commands (STOP_STREAM, CLEAR_STA) mid-connection.
- The owner key and saved Wi-Fi credentials are **plaintext in flash**.
  Protecting them against someone who physically dumps the flash chip
  requires the AmebaPro2's flash encryption with eFuse-held keys, a
  production-provisioning step (irreversible eFuse writes), not
  application code.
- ECDH runs in the BLE callback during a claim; expect a brief pause in BLE
  responses while it completes.

## Button

The onboard button (`PF_10`) acts on release; holding past a threshold
lights both LEDs so the user knows when to let go.

| Hold | Action |
|---|---|
| < 1 s | close pairing mode, if open |
| 1–3 s | nothing (treated as accidental) |
| 3–10 s | open pairing mode for 10 minutes |
| ≥ 10 s | factory reset: forget Wi-Fi and owner, reboot into pairing mode |

A button held during boot is ignored until it is released. Polarity is
inferred from Realtek's Arduino example (pressed reads HIGH); flip
`HAT_BUTTON_PRESSED_LEVEL` in `hat_button.c` if presses are not detected.
A custom button or capacitive pad replaces only `hat_button.c`; gesture
timing lives in `hat_press.c`.

## Status LEDs

| LED | Pattern | Meaning |
|---|---|---|
| Both | solid, while holding the button | release now to open pairing mode |
| Both | blinking together, while holding | release now to factory reset |
| Both | alternating | camera gave up after 3 restarts; power-cycle the hat |
| Blue | double-blink | pairing mode: ready for a phone to claim |
| Blue | short flash every 2 s | waiting for Wi-Fi provisioning (or between saved-network retries) |
| Blue | fast blink | joining Wi-Fi, switching networks, or reconnecting |
| Blue | solid | Wi-Fi connected |
| Green | off | not streaming |
| Green | fast blink | connecting/reconnecting to the RTMP ingest |
| Green | solid | publishing to the cloud |

Rows are in priority order. Blue is `PF_9`, green `PE_6` (`hat_led.c`).
One control task (`hat_control.c`) polls the button every 25 ms and renders
the LEDs every 125 ms from existing state. Polarity follows the Arduino
variant (lit on HIGH); flip `HAT_LED_ACTIVE_LEVEL` if the board shows the
inverse. A custom RGB LED replaces only `hat_led.c`; `hat_led_pattern.c`
decides what to show from a hardware-neutral `hat_indicator_state_t`.

## Saved network and telemetry

- After association and DHCP succeed, the hat saves that SSID/passphrase to the
  BT library's FTL application area (`hat_wifi_store.c`; the library offsets
  past its own bond records). It is plaintext in flash. Unchanged credentials
  are not rewritten.
- At boot, once BLE is up, the hat rejoins the saved network without the app.
  Failures retry after 15 s, doubling to a 2-minute cap, until one succeeds or
  the app sends its own `SET_STA`. Results nobody is connected to receive are
  cached as the FFE2 read value.
- An app `SET_STA` never waits behind the hat's own attempts. It takes over a
  boot-time rejoin, and a newer request aborts any Wi-Fi association in
  progress (initial, switch, or background recovery) within 100 ms. DHCP is the
  one step that cannot be interrupted; it finishes or hits the SDK's timeout
  first. During camera bring-up, the request waits and runs as a switch as
  soon as the camera is ready.
- While the camera runs, `SET_STA` switches networks instead of requiring a
  reset. The same, still-associated network reports `connected` immediately.
  A failed switch reports the error and keeps recovering the previous network.
- `{"cmd":"CLEAR_STA"}` forgets the saved network. The current association
  stays up until reboot.
- Once the camera runs, a subscribed client receives
  `{"event":"telemetry","kbps":…,"tx_kbps":…,"fps":…,"rssi":…,"stream":"…"}`
  every two seconds: encoder bitrate, bitrate actually handed to RTMP, encoder
  FPS, Wi-Fi RSSI (`null` while disconnected), and publisher state. Telemetry
  does not replace the cached FFE2 read value. Battery and temperature are not
  measurable on this board and are not reported.

## Hat info, camera restarts, and updates

- `{"cmd":"INFO"}` (owner only) replies
  `{"event":"info","id":"<Bluetooth address, 12 hex>","model":"AMB82_MINI_V1","fw":"0.2.0","camera":"ok|recovered|failed","camera_restarts":n,"camera_max":3}`.
  The app uses `id` to link the hat to the signed-in account on the backend
  (the platform's BLE device id differs per phone), `fw` to offer updates, and
  `camera` to explain restarts. `HAT_FIRMWARE_VERSION` in `hat_version.h` is
  the reported version: bump it for every release you publish.
- **Camera restarts.** SDK video initialization cannot be retried in place, so
  when the camera fails to start, produces no frames, or stalls for 30 s, the
  hat notifies
  `{"event":"camera_fault","reason":"video_start_failed|video_no_frames|video_stalled","action":"restarting","restarts":n,"max":3}`
  and reboots (`hat_camera_guard.c`). The streak survives reboots in FTL
  (offset 176). After the third restart in a row the next failure sends
  `"action":"stopped"`, the hat stays up with BLE and the alternating fault
  LEDs, and `INFO` reports `camera: failed`. A power cycle after giving up
  starts a fresh streak; 10 minutes of a running camera ends a streak. If the
  streak cannot be saved, the hat stops rather than risk a reboot loop.
- **Over-the-air updates.** The owner's app sends
  `{"cmd":"UPDATE_FW","sealed":...}` with sealed
  `{"url":"http://...","size":N,"sha256":"<64 hex>","version":"x.y.z"}`. The
  hat replies `{"event":"ota","status":"started"}` or `error` with `busy`,
  `no_wifi`, `streaming` (stop the stream first), `unsupported_flash`,
  `bad_url`, `bad_size`, or `bad_request`. It then downloads the build's
  `ota.bin` over plain HTTP on its own Wi-Fi, notifying
  `{"status":"downloading","progress":N}` every 10%, and finally
  `{"status":"rebooting","version":...}` or `{"status":"error","reason":...}`
  (`connect_failed`, `http_status`, `size_mismatch`, `download_failed`,
  `older_firmware`, `hash_mismatch`, `flash_failed`).
  - The image goes into the **inactive** firmware slot through the SDK's
    `ota_flash_NOR()`, which withholds the slot's boot label until the final
    block. `hat_ota_image.c` withholds that final block until the whole image
    matches the SHA-256 the owner sent over the encrypted channel, so a
    tampered, truncated, or interrupted download never becomes bootable and
    the running slot is never touched. Plain HTTP is acceptable because the
    hash, not the transport, authenticates the image.
  - The bootloader boots the slot with the newer build timestamp (manifest
    offset `0x2D4`), so the hat refuses images built before the running one.
  - There is no automatic rollback if a new build boots but misbehaves;
    reflash over USB. Starting a stream is refused while an update runs.

## Provisioning behavior

The worker exists before advertising. BLE waits for Wi-Fi hardware readiness
before starting the controller. Credential lengths, queue allocation, and
concurrent provisioning are checked. Wi-Fi association has a 30-second
deadline; DHCP has the SDK's separate timeout. The mobile pairing wait is 120 seconds to cover these stages, and ignores
cached values and stream-control events on the shared status characteristic.

Provisioning success requires DHCP and encoder frames. Failed Wi-Fi attempts
can be retried; a running camera accepts network switches (above). A camera
that fails to initialize is recovered by a bounded number of reboots (see
"Hat info, camera restarts, and updates"). Start/stop of RTMP itself
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

## Cloud image flash checkpoint (2026-09-30)

The outbound RTMP image was rebuilt with the deployed ingest address in the
ignored `cloud_config.h` and flashed over `/dev/cu.wchusbserial10`.
The flash tool reported `download success`. Image SHA-256:
`3fba28ecd17f8afe2d89dd05986435ad606e3b91a2d69b1908c4260584e16ec2`.
Server TCP connectivity and an RTMP handshake passed before flashing.
Reset, BLE provisioning, and actual board-to-cloud publishing still require
validation; a successful flash is not evidence of a working video stream.
Logs: `/tmp/hat-cloud-board-build.log`, `/tmp/hat-cloud-board-flash.log`.

## Queue overflow diagnosis and fix (2026-09-30)

Board serial diagnostics captured `reconnect reason=frame_queue_full` while
camera output stayed at 30 FPS. The cloud reader ended after 83.7 seconds
in a 30-minute baseline attempt; this failed the endurance check even though
FFmpeg returned exit code zero (stderr reported a demux I/O error).

The source now retains the RTMP connection after frame loss, drains affected
queued frames, skips dependent pictures, and sends a fresh sequence header
and IDR without resetting the stream timestamp origin. Enqueue is serialized
with recovery so old frames cannot be inserted after the queue is drained.
The six-frame memory bound remains. Network/socket failures still reconnect.
This fix was flashed successfully at 921600 baud on 2026-09-30.
Image SHA-256: `b40d306757b54f72066e5b99518efe95b73a8f9dd6870c038527988862d26fb5`.
Reset/provisioning and a new 30–60 minute continuous board/cloud test remain
pending. Flash log: `/tmp/hat-overflow-fix-flash.log`; extended serial capture:
`/tmp/hat-overflow-fix-serial.log`.

## Deferred endurance result (reviewed 2026-10-01)

The post-fix 30-minute cloud reader stopped after 520.2 seconds wall time,
with 509.57 seconds of decoded media and `Error during demuxing: Input/output
error`. FFmpeg returned zero despite ending early; this is not an endurance
pass. Serial capture includes queue resynchronizations that retained the
connection, plus later connection failures. The underlying later failure
has not been correlated conclusively. Hardware/endurance investigation was
deferred at the user's request while moving to YouTube output and overlays.
Evidence: `/tmp/hat-overflow-endurance-result.json`,
`/tmp/hat-overflow-endurance-progress.log`,
`/tmp/hat-overflow-endurance-ffmpeg.log`, `/tmp/hat-overflow-fix-serial.log`.
