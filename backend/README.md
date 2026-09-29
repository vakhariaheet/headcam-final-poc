# Backend — Auth API

A small TypeScript/Fastify service in front of the `db/` Postgres instance,
providing real email/password authentication for the UmpireHat app —
distinct from the OAuth *broadcast destination* stubs in the Flutter app
(YouTube/Facebook, still mocked, see `mobile/README.md`).

This is intentionally scoped to auth only. The database already has tables
for devices, matches, stream sessions, telemetry, and OAuth integrations
(spec §7.2) that this service doesn't touch — those would be separate
follow-up endpoints.

## Endpoints

| Method | Path                   | Auth   | Body                                         |
| ------ | ---------------------- | ------ | --------------------------------------------- |
| POST   | `/api/v1/auth/signup`  | —      | `{ email, password, firstName, lastName? }`  |
| POST   | `/api/v1/auth/verify-email` | — | `{ verificationToken, code }` |
| POST   | `/api/v1/auth/resend-verification` | — | `{ verificationToken }` |
| POST   | `/api/v1/auth/login`   | —      | `{ email, password }`                         |
| GET    | `/api/v1/auth/me`      | Bearer | —                                              |
| GET    | `/health`              | —      | — (unversioned — standard practice for health checks) |

Signup returns an email-verification challenge. Verification and login return
`{ token, user }`; `/me` returns `{ user }`.
`user` is `{ id, email, firstName, lastName, role }`. Passwords are hashed
with bcrypt (12 rounds) — never stored or returned in plaintext. Sessions
are stateless JWTs (30-day expiry), signed with `JWT_SECRET`.

Verification codes expire after 10 minutes, allow five attempts, and can be
resent after 30 seconds. Development responses include `developmentCode` when
SMTP is absent. Production requires SMTP and never returns the code.

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
