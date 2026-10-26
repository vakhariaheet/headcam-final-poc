# Backend — Auth API

A small TypeScript/Fastify service in front of the `db/` Postgres instance,
providing real email/password authentication for the UmpireHat app —
distinct from the OAuth *broadcast destination* stubs in the Flutter app
(YouTube/Facebook, still mocked, see `mobile/README.md`).

It also links hats to accounts and serves firmware releases for over-the-air
updates (below). Matches, stream sessions, and telemetry tables (spec §7.2)
are not served here yet.

## Endpoints

| Method | Path                   | Auth   | Body                                         |
| ------ | ---------------------- | ------ | --------------------------------------------- |
| POST   | `/api/v1/auth/signup`  | —      | `{ email, password, firstName, lastName? }`  |
| POST   | `/api/v1/auth/verify-email` | — | `{ verificationToken, code }` |
| POST   | `/api/v1/auth/resend-verification` | — | `{ verificationToken }` |
| POST   | `/api/v1/auth/login`   | —      | `{ email, password }`                         |
| GET    | `/api/v1/auth/me`      | Bearer | —                                              |
| GET    | `/api/v1/devices`      | Bearer | — (your linked hats, `{ items }`)              |
| PUT    | `/api/v1/devices/{serialNumber}` | Bearer | `{ hardwareModel, firmwareVersion, cameraRestarts, cameraFailed }` |
| DELETE | `/api/v1/devices/{serialNumber}` | Bearer | — (unlink one of your hats; 204)     |
| GET    | `/api/v1/firmware-releases?hardwareModel=&limit=` | Bearer | — (newest first, `{ items }`) |
| GET    | `/api/v1/firmware-releases/{id}/image` | — | — (the image, for the hat itself) |
| GET    | `/health`              | —      | — (unversioned — standard practice for health checks) |

Signup returns an email-verification challenge. Verification and login return
`{ token, user }`; `/me` returns `{ user }`.
`user` is `{ id, email, firstName, lastName, role }`. Passwords are hashed
with bcrypt (12 rounds) — never stored or returned in plaintext. Sessions
are stateless JWTs (30-day expiry), signed with `JWT_SECRET`.

Verification codes expire after 10 minutes, allow five attempts, and can be
resent after 30 seconds. Development responses include `developmentCode` when
SMTP is absent. Production requires SMTP and never returns the code.

### Hats and firmware

- **Linking.** After the app proves ownership of a hat over BLE, it reads the
  hat's `INFO` and calls `PUT /api/v1/devices/{serialNumber}` (the hat's
  Bluetooth address, `AABBCCDDEEFF`). The first link returns 201, later
  reconnects 200 and refresh `firmwareVersion`, `lastSeenAt`, and camera
  health. A link from another account moves the hat there: the BLE claim,
  which needs the hat's button, is the authority. The backend cannot verify
  that claim itself, so anyone who knows a serial number could relink it;
  production hats need a per-device factory key the backend checks first.
  Linking only records ownership for the account; it grants no control over
  the hat, which still requires the owner key on the phone.
- **Releases.** Publish a build's `ota.bin` (bump `HAT_FIRMWARE_VERSION` in
  `firmware/amb82_hat_native/src/mmfv2_video_example/hat_version.h` to the
  same version first):
  ```bash
  npm run build
  npm run firmware:publish -- --model AMB82_MINI_V1 --version 0.3.0 \
    --file ~/Desktop/ddev/ameba-rtos-pro2/project/realtek_amebapro2_v0_example/GCC-RELEASE/build/ota.bin \
    --notes "What changed"
  ```
  It records the size and SHA-256 and copies the image into `FIRMWARE_DIR`.
  In the container: `docker compose exec api npm run firmware:publish -- ...`
  with the file under `./firmware-releases/`.
- **Downloads.** The app hands the hat a release's `downloadUrl`, size, and
  SHA-256 (sealed over BLE); the hat downloads the image itself, with no
  token, over **plain HTTP** (it verifies the hash instead of using TLS). So
  `downloadUrl` must be an `http://` address reachable from the hat's Wi-Fi:
  set `FIRMWARE_DOWNLOAD_BASE_URL` (e.g. `http://192.168.1.20:4000`). Without
  it the app's own origin is used, which fails with 503 when that is HTTPS or
  localhost. Images are served with an exact `Content-Length`, because the
  hat does not accept chunked responses.

Errors always come back as a uniform envelope:
```json
{ "error": { "code": "INVALID_CREDENTIALS", "message": "Invalid email or password" } }
```
See `src/errors/ApiError.ts` for the full set of codes.

## Architecture

Follows a controller/service split per-module rather than routes doing
DB access directly:
- **`auth/auth.routes.ts`** — a Fastify plugin wiring HTTP verbs+paths to
  controller functions, registered under the `/api/v1/auth` prefix in
  `app.ts`.
- **`auth/auth.controller.ts`** — thin HTTP layer: reads `request`, calls
  the service, shapes `reply`. No DB access or business rules.
- **`auth/auth.service.ts`** — the actual business logic (validation,
  hashing, DB queries, session issuance). Throws `ApiError` on failure;
  knows nothing about Fastify.
- **`app.ts`** — assembles the Fastify app (the `@fastify/cors` plugin,
  routes, the centralized error handler). Kept separate from `server.ts`
  (which just calls `.listen()`) so the app is easy to test without binding
  a port.
- **`errors/ApiError.ts`** + **`middleware/errorHandler.ts`** — every
  thrown `ApiError` gets serialized into the uniform error envelope above by
  one central `setErrorHandler`, instead of each route shaping its own
  error JSON.

## Running it

Requires the `db/` Postgres container running (`cd db && docker compose up -d`)
— this service was built and tested against it directly.

**Local (fastest for iteration):**
```bash
cd backend
npm install
npm run dev   # tsx watch src/server.ts, Fastify listens on :4000
```

**Containerized** (joins `db/`'s network, reaches Postgres by hostname):
```bash
cd backend
docker compose up --build
```

## Linting

Enforces the project's Airbnb TypeScript style requirement automatically via
[`eslint-config-airbnb-extended`](https://github.com/eslint-config/airbnb-extended)
(the actively-maintained flat-config successor to the now-archived
`eslint-config-airbnb-typescript`), on the strict Node+TypeScript ruleset —
see `eslint.config.mjs`. Two rules are deliberately overridden there
(`no-console`, since this server has no logger yet, and
`import-x/prefer-default-export`, to stay consistent with the named-export
style already used throughout `src/`) — both with a comment explaining why.

```bash
npm run lint       # eslint .
npm run lint:fix   # eslint . --fix
```

## Schema change

`db/init/002_add_auth.sql` adds `password_hash TEXT NOT NULL` to `users` —
the spec's original `users` table (§7.2) had no password column. Applied to
the already-running `db/` container via `ALTER TABLE` (init/ scripts only
run on a fresh volume, per `db/README.md`); a fresh `docker compose up` on
`db/` picks it up automatically since it's now file `002_*`.

`db/init/004_email_verification.sql` adds `users.email_verified_at` and the
hashed verification-code table. Apply it manually to an existing database;
Docker init scripts only run automatically for a fresh database volume.

`db/init/006_devices_firmware.sql` makes `devices.ble_uuid` nullable (every
hat advertises the same service UUID, so it cannot identify one), adds
link/health columns to `devices`, and creates `firmware_releases`. Apply it to
an existing database with
`docker exec -i umpirehat-postgres psql -U umpirehat umpirehat < db/init/006_devices_firmware.sql`.

## Tests

The integration tests need a disposable database on `127.0.0.1:25432` (they
refuse any other `DATABASE_URL`), with every `db/init` script applied:

```bash
docker run -d --rm --name hat-backend-test -p 127.0.0.1:25432:5432 \
  -e POSTGRES_USER=umpirehat -e POSTGRES_PASSWORD=test_only -e POSTGRES_DB=hat_test \
  -v "$PWD/../db/init:/docker-entrypoint-initdb.d:ro" timescale/timescaledb:2.17.2-pg16
npm run build
DATABASE_URL=postgres://umpirehat:test_only@127.0.0.1:25432/hat_test \
  node --test tests/*.integration.cjs
docker stop hat-backend-test
```

## Verified

All confirmed against the running service during setup (and re-confirmed
after the controller/service/versioning retrofit):
- Signup returns 201 + a working token; the same email again returns 409
  with `EMAIL_ALREADY_EXISTS`.
- Login with the wrong password returns 401 with `INVALID_CREDENTIALS`;
  correct password returns 200.
- `/me` with a valid token returns the profile; with no token, 401.
- The old unversioned `/api/auth/*` paths correctly 404 now.
- The stored `password_hash` is a real bcrypt hash (`$2a$12$...`), confirmed
  directly in Postgres — never plaintext.

## Config

| Env var        | Default (dev only)                                              |
| -------------- | ----------------------------------------------------------------- |
| `DATABASE_URL` | `postgres://umpirehat:umpirehat_dev@localhost:5432/umpirehat`     |
| `JWT_SECRET`   | `umpirehat-dev-secret-change-me` — **override in any real deploy**|
| `PORT`         | `4000`                                                             |
| `NODE_ENV`     | `development`; use `production` in deployment                       |
| `SMTP_HOST`    | none; required in production for verification email                  |
| `SMTP_PORT`    | `587`                                                                |
| `SMTP_USER` / `SMTP_PASSWORD` | optional SMTP credentials                            |
| `SMTP_FROM`    | `CreasePoint <no-reply@creasepoint.local>`                           |
| `FIRMWARE_DIR` | `firmware-releases` (relative to the working directory)            |
| `FIRMWARE_DOWNLOAD_BASE_URL` | none; an `http://` origin the hat can reach, e.g. `http://192.168.1.20:4000` |
