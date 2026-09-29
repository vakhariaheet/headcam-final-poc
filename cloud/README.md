# Cloud Compositor Pipeline — Local POC

A POC of the UmpireHat cloud ingestion, compositing, and distribution worker.
It accepts the native hat's outbound RTMP stream, or an optional synthetic
RTSP source, and composites a scoreboard overlay into local verification outputs.

## Native hat ingress

The native firmware now initiates outbound RTMP; there is no local RTSP
listener on the hat in the new build. MediaMTX accepts that stream on TCP
1935, and the worker reads the same path over the private Docker RTSP
connection (`rtsp://mediamtx:8554/live/hat`). Host RTSP/API mappings are
loopback-only; public media ingress is the RTMP port.

For a real hat, start `mediamtx` and `worker` without the simulator:

```bash
docker compose --profile simulator stop simulator # if previously running
docker compose up -d --build mediamtx worker
```

Set the app's `HAT_INGEST_URL` to `rtmp://INGEST_HOST:1935/live/hat`, or use
the firmware's gitignored `cloud_config.h` default. The ingest hostname must
be reachable from the hat's Wi-Fi/hotspot, not a Docker service name or a
laptop-only loopback address. The URL can be supplied later without changing
the publisher code. Keep its path aligned with the worker's `RTSP_URL`.

The native stream is currently H.264 video only; the worker's audio mapping
is optional. `START_STREAM`/`STOP_STREAM` are sent over BLE by the updated app.
The cloud preview-vs-public-live split is not implemented by this change.
The Compose setup is still a POC with anonymous ingest and development auth
secrets; a real public server needs its own ingest authentication and TLS
configuration. The firmware client currently supports RTMP, not RTMPS.

## What's here

- **`mediamtx/`** — RTMP ingest / internal RTSP server (spec §2.2), off-the-shelf.
- **`simulator/`** — publishes a synthetic FFmpeg test pattern + tone over
  RTSP, standing in for the hat's real H.265 uplink until hardware exists.
- **`worker/`** — a session-scoped compositor: each broadcast is its own
  isolated Puppeteer page + FFmpeg process, created/stopped via a small
  authenticated HTTP control API (`/sessions`) and tracked durably in
  `db/`'s `stream_sessions` table (spec §7.2) so the registry survives a
  restart and could be shared across more than one worker instance. Each
  session renders a mock, transparent scoreboard overlay via Puppeteer
  (standing in for the real CricHeroes overlay page — see below),
  alpha-composites it onto the RTSP feed with FFmpeg, and writes the result
  to local files for verification (spec §5.2–§5.3).

## Running it

Requires `db/` and `backend/` running first (the worker's control API
verifies the same JWTs `backend/` issues, and stores sessions in `db/`'s
Postgres):

```bash
cd db && docker compose up -d
cd ../backend && docker compose up -d --build
cd ../cloud && docker compose --profile simulator up --build
```

First run pulls/builds images (including Chromium in the worker image), so
expect it to take a few minutes. Once running, the worker sits idle — it
launches its browser and control server, but doesn't start compositing
anything until a session is created.

Get a token (any signed-up account works — see `backend/README.md`), then
create a session:

```bash
TOKEN=$(curl -s -X POST localhost:4000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"..."}' | jq -r .token)

curl -X POST localhost:4100/sessions -H "Authorization: Bearer $TOKEN"
# => {"sessionId":"<uuid>","status":"LIVE"}
```

- MediaMTX logs should show the simulator's stream connecting on `live/hat`.
- The worker logs should show `session <id> ...` entries as FFmpeg starts.
- Output files appear under `./output/<sessionId>_a.ts` and `_b.ts`.

Create a second session with the same or a different token to confirm
concurrent, independent sessions — see "Verifying it worked" below.

## Verifying it worked

Open either output file in VLC or `ffplay`:

```bash
ffplay cloud/output/<sessionId>_a.ts
```

You should see the moving test-pattern video with a scoreboard bar in the
bottom-left corner (team names/score are still the mock overlay's own
defaults — see "Swapping in real destinations later"), plus the 440Hz test
tone audio — confirming the overlay is being captured from a live, changing
DOM and correctly alpha-composited onto the video rather than a static
image.

To exercise the reconnect path, stop just the simulator
(`docker compose --profile simulator stop simulator`) and confirm the worker's FFmpeg process
exits and retries every ~3s in its logs for each active session, then
restart the simulator (`docker compose --profile simulator start simulator`) and confirm every
session resumes.

**Session lifecycle**, with `$TOKEN` from above:
```bash
curl localhost:4100/sessions -H "Authorization: Bearer $TOKEN"
# => {"sessions":[{"sessionId":"...","status":"LIVE"}]}

curl -X POST localhost:4100/sessions/<sessionId>/stop -H "Authorization: Bearer $TOKEN"
# => {"sessionId":"...","status":"TERMINATED"} — output files stop growing
```
A different account's token gets `403 FORBIDDEN` on someone else's
session; no token at all gets `401 UNAUTHORIZED`.

## Swapping in real destinations later

- **Real broadcast targets:** `POST /sessions` accepts no output fields
  today — there's no real per-user YouTube/Facebook credential anywhere in
  this system yet (`broadcast_channels_provider.dart` in the mobile app is
  still fully mocked). Every session currently writes to the local files
  above. Once real OAuth destinations exist, the right shape is a
  server-resolved reference (a `destinationId` looked up from `db/`'s
  `stream_destinations` table), not a raw RTMPS URL accepted from a client.
- **Real CricHeroes overlay:** once a live match link exists, pass a real
  `overlay_web_url` (spec §5.1) as `POST /sessions`' `overlayUrl` field
  instead of the local `overlay.html`, and drop the mock scoring `<script>`
  in `overlay.html` (no longer needed).
- **Real hat stream:** once hardware is provisioned, each session would
  resolve its `rtspUrl` from a per-hat MediaMTX path instead of the shared
  `RTSP_URL` default, and the `simulator` service goes away.

## Known POC limitations (tracked as follow-ups, not gaps in this slice)

- **Capture method:** frames are captured via polling `page.screenshot()`
  rather than CDP's native screencast API, for simplicity and determinism.
  Throughput depends on host performance rather than being hardware-paced —
  fine for local verification, but the production worker should move to
  CDP screencast for sustained 30fps under load.
- **Apple Silicon performance:** `ghcr.io/puppeteer/puppeteer` only publishes
  an amd64 image (confirmed via `docker manifest inspect` — no arm64
  variant), so on an M-series Mac it runs under QEMU emulation. In testing
  this capped capture at ~6-7fps instead of 30 — the compositing pipeline
  itself is correct (verified by extracting and viewing a composited frame),
  just slower than real-time locally. This resolves itself once the real hat
  hardware supplies the video stream instead of the local simulator, or if
  run on an amd64 host/cloud instance.
- **Reconnect holding-loop (§8.1):** the real spec calls for a 30-second
  branded freeze-frame loop on the egress side while waiting for the source
  to return. This POC just lets FFmpeg exit and retries the whole pipeline
  every 3s — good enough to prove recovery happens, not a implementation of
  the branded holding-loop behavior itself.
- **No OAuth / broadcast API integration** (§8.3) — that's Sprint 4 scope
  per the roadmap, and orthogonal to validating the compositing mechanics.
- **No adaptive bitrate handling (§8.4)** — that logic lives on the edge
  node (rate-stepping in response to RTCP packet loss), not the cloud
  worker; the worker just absorbs whatever bitrate it receives.
- **Single worker instance:** sessions are tracked durably in `db/`'s
  `stream_sessions` table (`worker_host` records which instance owns each
  one), so a second worker instance could read/write the same registry —
  but nothing today actually routes a request to the right instance if it
  lands on the wrong one (it gets a clear `409 WRONG_INSTANCE` instead of
  silently failing or succeeding against the wrong session). A real
  multi-instance deployment needs a router/gateway in front of N worker
  instances using this same table — not built here. `MAX_SESSIONS_PER_INSTANCE`
  (default 4) caps how many concurrent sessions one instance will accept,
  tied to the Apple Silicon/CPU contention limitation above.
