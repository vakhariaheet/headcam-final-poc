# Cloud streaming worker

MediaMTX accepts the hat's outbound RTMP stream at `/live/hat`. The Node worker
reads it over RTSP/TCP, renders an app-controlled scoreboard with FFmpeg drawtext,
and publishes to the user's connected YouTube channel or records numbered TS
segments in `output/`. No browser capture process is required.

See [YouTube setup and deployment](YOUTUBE.md) for OAuth environment variables,
database migration, Flutter endpoints, and current limitations.

The optional simulator profile provides a synthetic camera input:
`docker compose --env-file ../.env --profile simulator up -d --build`.
Do not run the simulator on the same stream path while the real hat is publishing.
The database stack must already be running on the external `db_default` network.

Worker API requests use the backend's JWT: `POST /sessions`,
`GET /sessions/:id/status`, `PATCH /sessions/:id/scoreboard`, and
`POST /sessions/:id/stop`. Session creation accepts `target` (`youtube` or
`recording`), `title`, `privacy`, and `scoreboard`. Only the owning user can
inspect, stop, or edit a session. The shared hat path permits one active session.
