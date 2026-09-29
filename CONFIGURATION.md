# Configuration and secrets

No project `.env` file is required for the current local development setup.
The Docker Compose files supply development values directly. Node services
read process environment variables; they do not load `.env` files themselves.
A Compose `.env` supplies interpolation values only: it does not override
hardcoded service `environment` entries. Deployment must explicitly wire
real values into the container environment.

## Required configuration by component

| Component | Configuration | Source |
| --- | --- | --- |
| Native firmware | Wi-Fi SSID/password | Mobile app sends over BLE; no secrets header needed |
| Native firmware | RTMP ingest URL | App sends `HAT_INGEST_URL`, or optional ignored `cloud_config.h` copied from its committed example |
| Mobile app | `BACKEND_BASE_URL`, `CLOUD_BASE_URL`, `HAT_INGEST_URL` | Flutter `--dart-define` build/run arguments |
| Backend | `DATABASE_URL`, `JWT_SECRET`, `NODE_ENV`, `PORT`, `LOG_LEVEL` | Process/container environment; source has local development defaults |
| Backend email | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM` | Process/container environment; real email requires SMTP configuration |
| Worker | `DATABASE_URL`, `JWT_SECRET`, `RTSP_URL`, `CONTROL_PORT`, `WORKER_HOST`, `MAX_SESSIONS_PER_INSTANCE`, `NODE_ENV`, `LOG_LEVEL` | Process/container environment |
| Worker browser | `PUPPETEER_EXECUTABLE_PATH` | Optional process environment override; Docker image discovers Chrome |
| Database | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Database container environment |

The worker and backend must use the same JWT secret. Database connection
credentials must match the actual database role. Changing PostgreSQL container
environment values does not change credentials in an existing database volume.

The checked-in database password and JWT secret are development placeholders,
not production credentials. Replace them and configure ingest authentication
before EC2 deployment. The current native publisher supports plain RTMP only;
TLS/RTMPS remains unimplemented. Client build arguments are embedded in the
app and are not a secure place for server secrets.

## What belongs in Git

Keep source, tests, configuration examples, Docker definitions, dependency
lockfiles (including `mobile/pubspec.lock`), and vendor license notices.
Ignore real `.env` / `.env.*` files, private keys/signing files, local firmware
configuration, build products, dependencies, and recorded stream output.
Example environment files such as `.env.example` remain eligible for Git.

The external AmebaPro2 SDK and toolchain are not in this repository.
The native README documents their required wiring and SDK CMake changes;
a clean checkout alone does not contain the entire firmware build environment.
