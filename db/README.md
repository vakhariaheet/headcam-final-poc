# Database — Postgres 16 + TimescaleDB

The relational + time-series data tier from the Master Spec (§7): multi-tenant
orgs/users, hardware fleet, OAuth integrations, matches, broadcast sessions,
and a TimescaleDB hypertable for high-frequency telemetry.

## What's here

- **`docker-compose.yml`** — `timescale/timescaledb:2.17.2-pg16`, exposed on
  `localhost:5432` (user `umpirehat` / db `umpirehat` / password
  `umpirehat_dev` — local dev only, not for real credentials).
- **`init/001_schema.sql`** — the DDL from spec §7.2, applied verbatim, with
  one addition: a `SELECT create_hypertable('telemetry_samples', 'recorded_at')`
  call. The spec's narrative and BRIN index imply `telemetry_samples` should
  be a real TimescaleDB hypertable, but the DDL as written never actually
  converts it — without this call it would just be an ordinary table.

## Running it

```bash
cd db
docker compose up -d
```

The schema applies automatically on first startup via Postgres's
`docker-entrypoint-initdb.d` mechanism — check `docker logs umpirehat-postgres`
to confirm all `CREATE TABLE` / `CREATE INDEX` statements succeeded and
`create_hypertable` returned a row.

If you need to re-apply the schema after editing `init/001_schema.sql`, the
init scripts only run on a fresh volume:

```bash
docker compose down -v   # drops the data volume
docker compose up -d
```

## Verifying it

```bash
docker exec umpirehat-postgres psql -U umpirehat -d umpirehat -c "\dt"
docker exec umpirehat-postgres psql -U umpirehat -d umpirehat \
  -c "SELECT hypertable_name FROM timescaledb_information.hypertables;"
```

Both were confirmed working during setup: all 10 tables exist,
`telemetry_samples` is registered as a hypertable, and a full insert chain
(organization → user → device → match → stream_session → telemetry_samples,
joined back across all the foreign keys) round-tripped correctly.

## Notes for later integration

- **Connection string:** `postgres://umpirehat:umpirehat_dev@localhost:5432/umpirehat`
- Real deployments should not use the dev password above — inject real
  credentials via environment variables or a secrets manager instead of
  hardcoding them into `docker-compose.yml`.
- No ORM/migration tool is wired up yet — this is a single raw-SQL init
  script. Whichever backend service ends up owning writes (matching the
  cloud worker in `../cloud/`, or a future API layer) should adopt a proper
  migration tool (e.g. `node-pg-migrate`, `sqlx`, `goose`) once schema changes
  start happening incrementally instead of as one upfront DDL dump.
