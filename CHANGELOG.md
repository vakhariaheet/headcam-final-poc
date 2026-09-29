# Changelog

All notable changes to this project are documented here, newest first.
Entries are grouped by date rather than version number since this project
hasn't cut a release yet. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

## 2026-09-29 — firmware cleanup and configuration audit

- Retire four obsolete Arduino prototype folders; keep `amb82_hat_native`
  as the active firmware and update mobile documentation references.
- Remove the unused native Wi-Fi secrets header/example; provisioning uses BLE.
  Preserve retired files in a local backup outside the repository.
- Ignore environment variants, signing keys, native build artifacts, and Python
  caches while keeping environment templates and the Flutter lockfile eligible
  for version control.
- Document configuration sources and the remaining external SDK build setup
  in `CONFIGURATION.md`. Existing Compose credentials remain development-only.
- Validation: native flash target, provisioning and sanitized H.264 tests,
  and 12 ignore-rule checks passed. No common credential signatures found in
  Git-eligible files. No board flash performed.

## 2026-09-29 — outbound RTMP publisher (build and host tests; board test pending)

- Replace the native hat's RTSP sink with an outbound H.264 RTMP publisher.
  Pairing leaves it idle; BLE `START_STREAM`/`STOP_STREAM` control publishing.
  URLs are provided at runtime or through a gitignored firmware default.
- Use a bounded frame queue and dedicated sender, cancellable TCP I/O,
  exponential reconnect backoff, and fresh SPS/PPS+IDR after reconnect.
  Retry Wi-Fi association with the provisioned in-memory credentials.
- Vendor pinned LGPL librtmp with platform adapters. Initial transport is
  plain IPv4 RTMP and video only; RTMPS/TLS and AAC are not implemented.
- Wire app broadcast start/stop to the hat, including rollback on cloud start
  failure, independent shutdown attempts, and cleanup after unexpected cloud
  termination. Add tests for failure and cancellation paths.
- Enable MediaMTX RTMP ingress, restrict host RTSP/API mappings to loopback,
  make the simulator opt-in, and allow video-only compositor input.
- Validation: native flash target builds; packetizer sanitizer tests and host
  sender integration pass. MediaMTX receives and FFmpeg decodes 1080p video
  before/after server restart; stalled-handshake cancellation, retry STOP,
  duplicate-start rejection, and restart after STOP pass. Mobile and worker
  checks are recorded in the native README/test instructions.
- The outbound build has not been flashed on the board or tested against the
  real cloud endpoint, which is still being prepared. The prior board image
  remains the JXF37/local-RTSP checkpoint documented below.

## 2026-09-29 — native provisioning lifecycle and startup checks

- Wait for Wi-Fi hardware readiness before BLE controller initialization,
  fixing a startup race observed after disabling SDK fast connect.
- Initialize the provisioning queue/worker before BLE advertising; handle
  queue/task allocation failures and reject invalid or overlapping requests.
- Guard the asynchronous pipeline against repeated initialization and shared
  credential overwrites. Failed Wi-Fi attempts release the guard for retry;
  an active or partially initialized camera requires reset before reprovisioning.
- Use asynchronous Wi-Fi association with an elapsed-time deadline; check
  DHCP completion instead of accepting the SDK's fallback static address.
- Check pipeline setup results and require encoder frame callbacks before
  notifying `connected`. Preserve camera failure diagnostics without an
  automatic reset loop. Partial video teardown/recovery remains deferred.
- Disable the SDK's stored-profile fast connect and driver auto-reconnect,
  discovered during board testing to retry stale credentials independently.
- Board testing confirmed BLE provisioning and DHCP, then exposed GC2053
  sensor selection on the JXF37 board. Track the corrected F37 sensor header
  and regenerate its sensor/IQ package. The corrected image produces 30 FPS.
- Add host regression coverage for provisioning reservation, validation,
  allocation failures, completion routing, and retry behavior; update native
  setup/build instructions, including the required `flash` packaging target.
- Validation: host regression tests passed and native flash image built.
  The JXF37 image flashed successfully; serial confirms Wi-Fi initialization
  before BLE, advertising as `UmpireHat_C5F7`, successful BLE provisioning/DHCP,
  and 30 FPS encoder output without stale-network retries. FFmpeg decoded
  300 frames of 1080p30 H.264 over RTSP/TCP and exited successfully. Initial
  PPS warnings cleared once decoding began; long-duration and hardware
  failure/reconnect tests remain outstanding.

## 2026-09-21 — native SDK migration begins: Wi-Fi + camera + RTSP ported off Arduino

### Why

The Arduino wrapper's RTSP/StreamIO API is a closed, precompiled black box
with no access to raw encoded frames, which rules out ever building a
cloud-push (RTMP) client on top of it — needed so the hat can publish
directly to the cloud without a phone/laptop relay (rejected earlier for
UX reasons). Realtek's native RTOS SDK exposes that access via its MMF2
framework's custom-sink extension point. This is the first phase of that
migration; the Arduino sketches stay untouched as working fallbacks.

### Added
- `firmware/amb82_hat_native/` — new native-SDK firmware project (tracked
  source lives here; symlinked into the external `ameba-rtos-pro2` SDK
  checkout's build tree per the new README). Phase 1 scope: `hat_wifi_connect()`
  (programmatic `wifi_connect()`, replacing the stock example's AT-command-
  driven `ATW0`/`ATW1`/`ATWC` wait) + a near-verbatim port of the SDK's
  reference video/RTSP pipeline (`mmf2_hat_pipeline_init.c`), same 1080p30
  H.264 / 2 Mbps / 1s-keyframe-interval parameters as the Arduino firmware.
- Toolchain bring-up on this Mac: ARM GCC 10.3.1, the SDK's own
  `ameba-dev-pro2` MCP dev-tooling server (build/flash/serial-monitor
  tools), confirmed end-to-end against the SDK's stock example before any
  of this project's own code was involved.

### Known limitations
- **`VOE command 0x206 fail` / zero video frames** — Wi-Fi connects and RTSP
  reports ready, but no frames actually flow. Same error family as an
  already-documented, Realtek-confirmed SDK bug
  (`firmware/amb82_camera_test/README.md`), but reproduces on every boot
  here rather than intermittently; a Wi-Fi-timing settle-delay fix was
  tried and ruled out (error's internal timing stayed ~164ms regardless).
  Not yet isolated from a stock-example baseline. See the new README's
  "Known issue" section for full detail.
- BLE provisioning, RTMP publish, credential persistence, telemetry, and
  OTA are later phases of the same migration, not started yet.

## 2026-09-18 — real BLE pairing: firmware GATT service + Flutter client

### Added
- `firmware/amb82_hat_firmware/` — new sketch implementing the real Master
  Spec §4 pairing flow, replacing hardcoded `secrets.h` Wi-Fi credentials:
  advertises BLE service `FFE0`, accepts Wi-Fi credentials as JSON over
  write characteristic `FFE1`, and reports connect status/IP on
  read+notify characteristic `FFE2` — then starts the same proven 1080p30
  RTSP pipeline from `amb82_camera_test`. Requires the ArduinoJson library
  (documented in its README) to parse the provisioning payload.
- `mobile/lib/services/real_hat_connection_service.dart` — `flutter_blue_plus`-
  backed `HatConnectionService` implementation talking to that GATT
  service: filters scans by the advertised `UmpireHat_` name prefix, writes
  the credentials JSON to `FFE1`, awaits the status notification on `FFE2`.
- `NSBluetoothAlwaysUsageDescription` in `ios/Runner/Info.plist` — required
  for the BLE permission prompt to appear at all; was previously absent.

### Changed
- `hatConnectionServiceProvider` now constructs `RealHatConnectionService`
  instead of the mock — the "single swap point" the codebase's own doc
  comments had been pointing at since the mock was first written.
- `device_pairing_flow_test.dart` gained a scripted `_FakeHatConnectionService`
  test double (the old mock's behavior, now living in test/ instead of
  lib/) so its pairing-flow assertions don't depend on real BLE hardware
  under `flutter test`.
- `app_shell_test.dart` and `live_broadcast_screen_test.dart` now override
  `hatTelemetryProvider` with a fixed sample in the two tests that render
  telemetry-dependent UI and call `pumpAndSettle()` — the real service's
  `telemetryStream()` never emits (firmware doesn't push periodic
  telemetry over BLE yet, see below), which otherwise left a loading
  spinner animating forever and `pumpAndSettle()` never settling.

### Removed
- `mobile/lib/services/mock_hat_connection_service.dart` — no longer
  referenced anywhere in `lib/` once the real implementation replaced it
  at the provider.

### Fixed
- BLE scan not finding the hat in-app despite a generic BLE scanner seeing
  it: the firmware puts the `FFE0` service UUID in the scan *response*
  packet, not the primary advertisement, and iOS CoreBluetooth's
  `withServices` scan filter is unreliable against scan-response-only
  service UUIDs. Filter by the advertised `UmpireHat_` name prefix instead.
- Scan never completing: `FlutterBluePlus.scanResults` only emits on new
  advertisements and never pushes a closing event when scanning internally
  stops, so an `await for` loop relying on that hung forever once no new
  devices appeared. A `Timer` now force-closes the stream after the scan
  timeout elapses.
- `FFE1`/`FFE2` `setBufferLen()` hard-capped at 230 bytes by the AmebaPro2
  BLE stack (confirmed on real hardware: requesting 512 throws
  `requested buffer size too large, maximum of 230`) — well under a real
  signed-in session JWT's ~370 bytes. The Master Spec's `session_token`
  field is dropped from the `FFE1` payload entirely (the firmware never
  read it anyway); reinstating it needs a chunked/multi-write protocol.
- `credentialsWriteCB` crashed with a `Stack overflow UsageFault` partway
  through the Wi-Fi 4-way handshake: it called `connectToWifi()` and
  `startCameraStream()` directly, but BLE write callbacks run on the BLE
  stack's own task, which has a much smaller stack than `loop()`'s. The
  callback now only parses/validates and stores the request; `loop()`
  polls a `pendingProvisionRequested` flag and does the actual connect +
  camera/RTSP startup there instead.
- Board package silently drifted to Realtek AmebaPro2 **4.1.0** (which has
  the previously-documented VOE/sensor-init bug) after an apparently
  interrupted Arduino IDE core update left a stale local package index;
  reinstalled the pinned **4.0.9** and cleared the resulting stale build
  cache.

### Known limitations (deliberate, documented in the new firmware's README)
- No `session_token` over BLE — see the buffer-cap fix above. Pairing
  itself doesn't currently bind to a signed-in account.
- No credential persistence across power cycles yet (spec §8.1) — every
  boot waits for BLE pairing again.
- No periodic telemetry pushed over BLE yet (spec's `telemetry_samples`
  tick) — only one status message per pairing attempt. The real mobile
  service's `telemetryStream()` reflects this honestly by returning an
  empty stream rather than fabricating values.

## 2026-09-18 — firmware: first working AMB82-Mini camera stream

### Added
- `firmware/amb82_camera_test/` — new RTSP camera smoke-test sketch,
  confirmed working end to end (1080p30 H.264 over RTSP, verified in VLC).
  Structured so serial output distinguishes between the several distinct
  AMB82-Mini failure modes hit while bringing up the first physical board,
  instead of all of them looking like identical "no video."
- `videoConfig._gop = 30` (1-second keyframe interval, down from the SDK's
  80-frame/~2.7s default) so packet loss on a marginal Wi-Fi link shows as
  a small hiccup instead of a multi-second freeze-then-jump.

### Fixed
- The AMB82-Mini has no onboard antenna — it requires a separate IPEX/u.FL
  antenna accessory to be physically attached, without which Wi-Fi scans
  succeed but authentication never completes on any network
  (`Auth: 0` forever, regardless of SSID/security config). This was the
  root cause of the board failing to connect to two different real Wi-Fi
  networks; documented prominently in the new sketch's README so it isn't
  re-debugged as a network/config issue next time.
- Pinned the Arduino board package to Realtek AmebaPro2 **4.0.9**; 4.1.0/
  4.1.1 have an open upstream SDK bug (`VOE command 0x206 fail`, camera
  sensor init silently skipped) reproduced across multiple boards on the
  stock official example, not something fixable from application code.
- Playback stuttering and climbing `pts_delay`/`buffer deadlock` in VLC
  was isolated to the test router's RF environment via an A/B test against
  a phone hotspot (zero drops on hotspot, same board/sketch/settings) —
  not a board, antenna, or firmware issue.

## 2026-09-16 — signup verification and first-hat onboarding

### Added
- Redesigned Create Account form with full name, password requirements,
  terms acceptance, and Google/Apple placeholders.
- Server-issued email verification with hashed six-digit codes, ten-minute
  expiry, five-attempt limit, resend cooldown, SMTP delivery, and purpose-
  scoped challenge tokens.
- Verify Email, Account Created, and first-UmpireHat screens wired into the
  existing device-discovery flow.
- First-hat onboarding uses the dedicated `hat.png` product image.
- The product image now preserves its full 3:2 frame, and Account Created
  plays a one-shot confetti burst that respects reduced-motion settings.
- Development-only verification codes when SMTP is not configured.
- Regression tests for terms acceptance and the complete signup UI sequence.

### Security
- Verification tokens cannot authorize backend or cloud-worker endpoints.
- Login remains blocked until the email address is verified.

## 2026-09-15 — mobile: Welcome and authentication redesign

### Added
- Photo-led Welcome screen using `splash.png`, with Get Started and Sign In.
- Shared, scrolling authentication layout rendering `creasepoint-auth-arcs.svg`
  directly through `flutter_svg`, with outlined fields and blue arrow actions.
- Google/Apple sign-in controls that explain their current unavailability.
- Password recovery email-entry screen that explicitly reports no code was
  sent while backend recovery is unavailable.
- Reusable OTP and password-updated views for future recovery integration.
  OTP supports full-code paste/autofill and a 30-second resend cooldown;
  verification and resend require integration callbacks. These views are
  not wired into the production recovery flow yet.
- Tests for successful login routing, Welcome navigation on a small phone,
  OTP paste and verification, and resend cooldown behavior.

### Changed
- Signed-out startup opens Welcome; valid stored sessions still open Home.
- Login and Signup adopt the reference authentication design.

### Fixed
- Login and Signup now open `/home` and clear the authentication navigation
  stack, replacing references to the removed `/channels` route.
- Cropped unused whitespace from compact logo assets and tightened Login
  spacing so Create an account remains visible without scrolling on standard
  phone screens.

## 2026-09-15 — mobile: CreasePoint rebrand + pairing/broadcast flow split

### Added
- CreasePoint visual identity: new design tokens (`AppColors`, `AppSpacing`,
  `AppRadius`), typography, and logo assets, applied across a new
  Home / Live / Devices / Recordings / Settings bottom-nav shell
  (`app_shell.dart`).
- Hat pairing is now its own short flow, separate from starting a
  broadcast: BLE discovery (`device_discovery_screen.dart`) → Wi-Fi
  credentials with a single "Pair Hat" action (`hotspot_provisioning_screen.dart`).
- Multi-hat support: previously-paired hat ids persist locally
  (`services/paired_hats_store.dart`), and a new
  `screens/select_hat_screen.dart` lets the umpire reconnect to any
  paired hat that's currently reachable via BLE scan, instead of
  re-pairing every time.
- Broadcast-channel connection (YouTube/Facebook) is now a one-time,
  user-level setting persisted locally (`services/channel_connection_store.dart`)
  and managed from Settings, instead of a mandatory OAuth step repeated
  before every broadcast.
- `state/shell_navigation_provider.dart` — lets screens pushed on top of
  the shell (Match Setup, Preflight) redirect into a specific bottom-nav
  tab without a global navigator key.
- Live screen rebuilt to match design.md §13's actual mockup: camera
  preview placeholder with live stats overlay, battery/temperature/signal
  grid (shared `widgets/metric_column.dart`), score-overlay status card,
  and an "End Broadcast" action.
- Device Card (`widgets/device_card.dart`) rebuilt to match design.md
  §12, branching between "not connected" (Pair New Hat / Choose Existing
  Hat) and "connected" (live telemetry + Start Broadcast) states.
- `test/device_card_test.dart` — new coverage for the Device Card's
  branching states.

### Changed
- Starting a broadcast is now its own flow (Match Setup → Preflight →
  Live), reachable only once a hat is connected, and no longer includes a
  channel-connection step.
- `match_setup_screen.dart` no longer has per-match platform checkboxes;
  it reads whichever channels are already connected and prompts a jump to
  Settings if none are.
- Preflight's successful "Start Broadcast" now switches the shell to the
  Live tab and pops back to it, instead of pushing a standalone `/live`
  route.
- Device Discovery screen restyled with Overline section labels and
  `StatusPill` connection states.
- "Emergency Kill Switch" renamed to "End Broadcast" to match design.md's
  own wording.

### Removed
- `broadcast_channels_screen.dart` and the `/channels` and `/live` routes
  (channel connection lives in Settings now; Live is a shell tab, not a
  pushed screen).
- The Home screen's old multi-row Readiness checklist card, superseded by
  the Device Card's own connection-state branching and the Settings
  channel banner.

### Fixed
- Ran `dart format` across `lib/` and `test/` — 15 files had drifted from
  canonical formatting, invisible to `flutter analyze` alone.
- Added missing `///` doc comments on `SettingsScreen` and
  `SelectedShellTabNotifier`, found during an Effective Dart review pass.

*(Earlier history — initial backend/cloud/db/mobile POC scaffolding —
predates this changelog and isn't reconstructed here.)*
