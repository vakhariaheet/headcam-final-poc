# YouTube and app-controlled scoreboard

The hat publishes to MediaMTX. The worker reads RTSP, adds the app's scoreboard,
encodes H.264 with silent AAC audio, and sends RTMPS to the connected user's
YouTube channel. Google refresh tokens and ingest keys are encrypted in Postgres;
the app never receives them. Facebook and CricHeroes overlays are not implemented.

## Configuration

The repository root `.env` contains placeholders and is ignored by Git.
Use `.env.example` to recreate it. Configure:

- `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`: a Google OAuth **Web application** client.
- `GOOGLE_REDIRECT_URI`: exactly `https://YOUR_API_HOST/api/v1/youtube/oauth/callback`.
  Register the identical URI in Google Cloud Console. Enable YouTube Data API v3,
  configure the consent screen, and add your account as a test user while testing.
- `YOUTUBE_TOKEN_KEY`: 32 random bytes encoded as 64 hex characters.
- `WORKER_API_SECRET`: a separate random secret of at least 32 characters, shared
  by backend and worker. `openssl rand -hex 32` generates either secret locally.
- `BACKEND_INTERNAL_URL`: normally `http://api:4000` on the shared Docker network.

Preserve the token encryption key: changing it makes existing connections unreadable.
Do not put these secrets in Flutter Dart defines or commit `.env`.
Backend and worker must use the same database and JWT secret. Existing Compose
files still contain development database/JWT defaults; replace them for deployment.
Use your HTTPS proxy for backend and worker HTTP APIs. Keep Postgres private.

## Existing deployment upgrade

Back up the database, then apply the new migration once from the repository root:

```bash
docker exec -i umpirehat-postgres psql -U umpirehat -d umpirehat < db/init/005_youtube.sql
(cd backend && docker compose --env-file ../.env up -d --build)
(cd cloud && docker compose --env-file ../.env up -d --build worker)
```

Confirm the database container name on your server before running the migration.
Mounting init scripts does not migrate an existing Postgres volume. The worker
runs as a non-root user; ensure `cloud/output` is writable by container UID 1000
if using server recording mode.

Build/run Flutter with your real endpoints:

```bash
flutter run \
  --dart-define=BACKEND_BASE_URL=https://YOUR_API_HOST \
  --dart-define=CLOUD_BASE_URL=https://YOUR_WORKER_HOST \
  --dart-define=HAT_INGEST_URL=rtmp://217.216.58.69:1935/live/hat
```

Settings → Connect YouTube opens Google consent in the browser. Return to the
app and tap Refresh connection. Preflight lets you choose YouTube or server
recording, a title, visibility (private by default), and the initial scoreboard.
On Live, edit and save the scoreboard to update the encoded video. Stop ends the
YouTube broadcast. The app account remains the existing email/password account;
Google authorization connects that account's broadcast channel.

## Operational limits and validation

Only one session may use the shared `live/hat` path at a time. Scoreboard updates
require the owning app account. Team names use the bundled DejaVu font; scripts
without glyph coverage require a suitable `OVERLAY_FONT_FILE` in the image.
No microphone track is published yet; YouTube receives silent audio.

Worker `LIVE` means FFmpeg has emitted video, not that YouTube has confirmed
viewer playback. YouTube live eligibility and project/account restrictions still
apply. A real channel test is required after credentials are configured.
Automatic YouTube stop is disabled so a brief input gap does not intentionally
end the broadcast; explicit Stop and worker restart cleanup end it. Encoder
retries are bounded to ten consecutive short failures. Recording retries create
separate numbered TS segments. This does not resolve the deferred hat/VLC
endurance issue or establish a multi-hour reliability guarantee.

Verified locally: backend integration tests with a disposable Postgres database
and mocked Google responses; scoreboard validation/auth tests; Flutter tests;
and real Docker FFmpeg encoding of 1080p H.264/AAC with the text overlay. Actual
Google consent, YouTube ingest, and end-to-end hardware broadcast are not yet tested.

Reference: [Google web-server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server),
[YouTube Live API](https://developers.google.com/youtube/v3/live/docs).
