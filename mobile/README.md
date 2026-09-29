# CreasePoint — Buildable-Without-Hardware Slice

The Flutter companion app for the UmpireHat wearable, from the Master Spec
(§6): auth, hat pairing, hotspot provisioning, CricHeroes match setup,
pre-flight checks, and the live broadcast console, plus a Home ·
Live · Devices · Recordings · Settings shell around it. Built and verified
without any hat hardware.

## What's real vs. mocked

**Real, not mocked:**
- **User authentication** (`lib/state/user_auth_provider.dart`,
  `lib/screens/login_screen.dart`, `lib/screens/signup_screen.dart`) — real
  email/password signup/login against `backend/`'s API, which itself writes
  to the `users` table in `db/`. Sessions are JWTs stored via
  `lib/services/user_session_store.dart` (`flutter_secure_storage`); app
  start (`lib/screens/auth_gate.dart`) validates any stored session against
  the backend and skips login if it's still valid. This is distinct from
  the broadcast-channel OAuth below.
- **Email-verified signup** — account creation proceeds through a server-issued
  six-digit challenge, Account Created confirmation, and first-hat onboarding.
  Development shows an explicit code when SMTP is not configured; production
  sends it by email.
- CricHeroes match URL parsing (`lib/services/cricheroes_parser.dart`) —
  implements the exact regex from spec §5.1, unit-tested against the spec's
  own example URL.
- Hotspot credential storage (`lib/services/secure_credential_store.dart`) —
  genuine `flutter_secure_storage` (iOS Keychain / Android Keystore) usage.
- Pre-flight tilt check (`lib/state/preflight_provider.dart`) — reads the
  phone's real accelerometer via `sensors_plus`. Note: the iOS Simulator
  reports a static, near-flat reading, so the ">10° tilt" failure path won't
  visibly trigger there — the sensor integration itself is real.
- Riverpod-based app state and navigation shell, per spec §6.1.

**Mocked behind a swappable interface:**
- BLE scanning/pairing/telemetry — `lib/services/hat_connection_service.dart`
  is the abstract interface; `mock_hat_connection_service.dart` is the only
  implementation today. Swapping in `flutter_blue_plus` against a real hat
  is a single implementation swap — nothing in `state/` or `screens/` needs
  to change.
- Broadcast destination OAuth (`lib/state/broadcast_channels_provider.dart`,
  `lib/screens/broadcast_channels_screen.dart`) — connecting YouTube/
  Facebook as *destinations* is still stub buttons that flip local state.
  Real Google/Meta OAuth needs API credentials this build doesn't have. Not
  to be confused with the real user auth above — this only decides where
  the stream gets simulcast to.
- Audio VU meter and uplink speed test (Screen 5) — simulated readings.
- Live telemetry (Screen 6) — a timer-driven fake battery/temp/bitrate feed.

**Not attempted in this slice:**
- Screen 7 (Dynamic Island / Live Activity) — needs a native iOS
  ActivityKit/WidgetKit extension, a different toolchain from the Dart app.
- Real OAuth token flows and YouTube/Meta API calls (spec §8.3).

## Design system

Follows `design.md`'s CreasePoint design system: `lib/theme/app_theme.dart`
defines the brand palette (navy/white structure, Crease Blue as the one
interactive accent, green/amber/red status colors), the Inter typeface
(`google_fonts`), and component themes (buttons, inputs, cards, nav bar)
applied consistently across every screen. `lib/widgets/brand_header.dart`
renders the CreasePoint logo lockup (`lib/assets/creasepoint-*.png`) shown
on the splash screen, Login, and Signup. `lib/theme/app_theme.dart` also
defines a separate dark "broadcast mode" theme used only by the Live
console (design.md §3).

## Running it

Requires `backend/` running (see `backend/README.md`) for the login/signup
screens to work — without it, `AuthGate` will time out waiting for a
session check and land on the login screen, but signing in/up will show a
"couldn't reach the server" error until the backend is up.

The Flutter SDK in this environment lives at `~/flutter` (not on `PATH` by
default):

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd mobile
flutter pub get
flutter run -d "iPhone 17"   # or: flutter devices, to see what's available
```

## Verifying it

```bash
flutter analyze   # no issues
flutter test       # unit + widget tests
```

Confirmed during setup: the app boots to the new branded login screen and
renders correctly on the iOS Simulator (verified via a live screenshot, not
just a successful compile), against the real running `backend/` service.

**Two real bugs were caught and fixed during verification:**
- Several screens used `Spacer()` inside a non-scrolling `Column`, which
  triggered a `RenderFlex overflowed` error on the Hotspot Provisioning
  screen once the on-screen keyboard reduced the available height. Fixed by
  switching those screens' bodies to `SingleChildScrollView`. There's a
  regression test for this in `test/match_setup_screen_test.dart` ("does
  not overflow with a shrunk viewport") that reproduces the failure by
  shrinking the test viewport — confirmed to fail against the old
  `Spacer()`-based code and pass against the fix.
- `restoreSession()` awaited the secure-storage read with no timeout, which
  would strand the app on the splash screen indefinitely if that platform
  channel call ever stalls (confirmed happening under the widget-test
  binding, but the same risk exists on a real device with a blocked
  Keychain/Keystore). Fixed with a 5s timeout that falls back to
  "unauthenticated" rather than hanging forever.

## Next steps once hardware/credentials exist

- `HatConnectionService` is now backed by `RealHatConnectionService`
  (`flutter_blue_plus`), talking to the GATT service
  `firmware/amb82_hat_native` advertises — see the native firmware README for
  the wire protocol. Still open: firmware doesn't persist credentials
  across power cycles or push periodic telemetry over BLE yet (both
  flagged in that README), so `telemetryStream()` returns an empty stream
  against real hardware for now.
- Wire up real Google/Meta OAuth (needs API credentials) in
  `lib/state/broadcast_channels_provider.dart`.
- Build the Dynamic Island / Live Activity native extension (Screen 7).
- Replace the simulated audio/uplink readings in
  `lib/state/preflight_provider.dart` with a real mic level and bandwidth probe.
- For a physical device (rather than the simulator), `AuthApiClient`'s
  default `http://localhost:4000` won't resolve — pass the host machine's
  LAN IP as `baseUrl` instead.
