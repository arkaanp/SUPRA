# Supra backend: database setup and tests

The tracked application lives here. `supra_db_queries.sql` is a **legacy
reference** containing executable example DML; do **not** run the whole file
against a database. Use only `migrations/` for schema and `seeds/` for optional
demo records. Neither migration nor seeding happens on ordinary server startup.

## Fresh database

Create a PostgreSQL database (local or Supabase). Set `DATABASE_URL` to a
PostgreSQL connection string with permission to create tables and indexes.
Use a server-only database role that bypasses RLS (e.g. Supabase `postgres`):
Axum enforces ownership in its queries. Set `SUPABASE_URL` to the same project
used by Flutter; it must issue asymmetric ES256/RS256 access tokens.
For local development, copy `.env.example` to `backend/.env` and replace the
placeholder URL; the backend loads that file for both server and `migrate`
commands. `backend/.env` is ignored by Git. Environment variables already set
in the shell take precedence over values in `.env`; deployment can use environment
variables without a file. From `backend/`:

```sh
cargo run --locked -- migrate
cargo run --locked
```

The `migrate` command applies the versioned SQLx migrations and exits. Repeating
it is safe: SQLx records applied versions in `_sqlx_migrations`. Schema changes
should be **new migration files**, never edits to already-applied migrations.
The server requires the schema to exist; it does not apply migrations on startup.
The auth migration removes password hashes and blocks direct Data API access
to application tables. Back up existing data before applying it. Legacy profile
UUIDs are preserved but are not Supabase Auth users: migrate ownership explicitly,
never by matching email.

**Populated Supabase projects:** this initial migration uses `IF NOT EXISTS`
and matches the seven-table baseline schema. Back up the database and compare
columns, constraints, indexes, and data to the baseline before running it.
`IF NOT EXISTS` does not detect or repair schema drift. Do not run the legacy
reference file to adopt an existing database. Future changes need additive,
reviewed migrations and compatibility notes.

For an explicitly **disposable/demo** database only, install `psql` and run the
seed after setting `DATABASE_URL` in your shell (`psql` does not read Rust's
`.env` file):

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -v demo_user_id='YOUR_AUTH_USER_UUID' -v demo_email='YOUR_AUTH_USER_EMAIL' \
  -f seeds/demo.sql
```

The seed has stable IDs for one demo user and is idempotent. Create that user
through Supabase Auth first; SQL does not create an Auth account. Forecast values
are illustrative, not live ML output. Never seed production.

## Authentication and profiles

Flutter signs in with Supabase Auth and sends `Authorization: Bearer <access_token>`
to Axum. Set `SUPABASE_URL` and optionally `SUPABASE_JWT_AUDIENCE` (defaults to
`authenticated`). Axum verifies signature, issuer, audience, expiry, subject
UUID and role via JWKS. HS256 tokens are unsupported; migrate the project's
signing keys before use. No signing secret or service-role key belongs in Flutter.

After sign-in, `POST /api/users` with `{ "full_name": "Your Name" }` upserts the
profile; email and UUID come from the verified token. `GET /api/users` returns
only that user's profile. Deleting the profile does **not** delete its Supabase
Auth account. Ordinary clients cannot create/delete predictions or create
notifications: those writes belong to future server-side jobs.

## Tests

Unit/router tests run without PostgreSQL:

```sh
cargo test --locked
```

The database-backed API smoke test is ignored by default: provision a **dedicated**
PostgreSQL database whose name ends in `_test`, with no important data. Set
`SUPRA_TEST_DATABASE_URL` to it (different from `DATABASE_URL`) and run:

```sh
export SUPRA_TEST_DATABASE_URL='postgres://USER:PASSWORD@HOST:5432/supra_test'
cargo test --locked -- --ignored
```

The test applies migrations to this database, exercises authenticated CRUD,
cross-user ownership checks, and prediction/notification reads, and cleans up
its fixtures on success. `cargo test` without `-- --ignored` reports it as
ignored; a green unit-only run is **not** a verified database run.
No demo seed or real Supabase account is needed: tests use locally signed JWTs
and a mock JWKS endpoint. Test against real Supabase before production deployment.

## Initial user-facing data sources

Authenticated `GET /api/conditions/current?latitude=-6.2&longitude=106.82`
combines Open-Meteo weather (optional BMKG fallback), nearby OpenAQ PM2.5 and
TomTom nearest-road traffic. Set `OPENAQ_API_KEY` and `TOMTOM_API_KEY` in
`backend/.env`. Missing/failing providers are reported separately without
discarding healthy signals. BMKG requires the matching optional `adm4` village
code and returns an explicitly labeled upcoming forecast, not an observation.
See [the conditions contract](docs/current-conditions.md) for response fields,
coverage, attribution, timeouts, credential setup and verification limitations.

## Prototype bug/data migration

Run `cargo run --locked -- migrate` before using the updated client. See
[the migration contract](docs/prototype-migration.md) for confirmed journey fields,
backend-only Gemini behavior and truthful route/environmental display guarantees.

Set `GEMINI_API_KEY` and a supported `GEMINI_MODEL` on the server only. Missing
configuration or provider errors return 503, never a simulated environmental reply.

Avatar uploads are decoded, bounded to 4096×4096/5 MB, resized to at most 512×512,
and re-encoded as PNG (no original metadata). `AVATAR_STORAGE_DIR` is a runtime
directory relative to the backend working directory or an absolute durable-volume
path. Set `PUBLIC_BASE_URL` to the externally reachable origin (HTTPS in
production); request Host headers are not used to construct links. Avatars are
public profile images. Replacements/account deletion clean up referenced,
same-origin owned files; unrelated/legacy files are not bulk-deleted. Runtime
uploads are Git-ignored. Local files must be mounted on persistent/shared storage
for production replicas; this does not provision object storage automatically.

## Commute features and alerts

See [the commute features contract](docs/commute-features.md) for endpoints,
validation rules, and background alert evaluation details.

Run `cargo run --locked -- migrate` to apply `20261109000000_commute_features.sql`.
Saved places (`/api/places`) and routines (`/api/routines`) provide user-isolated
entities for daily travel. Routing for walking and motorcycle modes uses Valhalla,
while public transit routes query an OpenTripPlanner 2.x GTFS GraphQL endpoint.

Background alert evaluations can be scheduled by setting `ALERTS_ENABLED=true`.
When enabled, an asynchronous worker evaluates due targets once per minute,
limiting checks to at most once per 5 minutes per target. Incident news alerts require
a configured JSON feed URL (`NEWS_INCIDENTS_URL`). Users can also queue manual checks
via `POST /api/alerts/evaluate`, which responds with HTTP 202 Accepted.

## API errors and input format

### Public health endpoints

| Request | Success | Failure |
| --- | --- | --- |
| `GET /health/live` | 200 `{"status":"ok"}` | No dependency check |
| `GET /health/ready` | 200 `{"status":"ready"}` | 503 `{"error":"Service not ready","code":"unavailable"}` |

These probes do not require a bearer token or call Supabase Auth. Readiness
executes `SELECT 1` against PostgreSQL with a **two-second total timeout**,
including connection-pool acquisition. It checks connectivity only, not schema
compatibility or Gemini/ML availability. Liveness stays successful if the
database becomes unavailable after startup; startup still requires the initial
database connection to succeed. Use readiness, not liveness, to gate traffic.

All existing resource endpoints remain protected. Unknown paths return JSON
404 (`not_found`) without token verification. Unsupported methods on public
health paths return JSON 405 (`method_not_allowed`); on protected resource paths
they require authentication first (401 without a valid token, 405 with one).
405 responses preserve the HTTP `Allow` header. `HEAD` follows Axum's normal GET
behavior and returns headers/status without a body.

Handler failures return JSON such as `{"error":"Resource not found","code":"not_found"}`.
The codes/statuses are `unauthorized` (401: invalid/missing token),
`invalid_request` (400: malformed input or invalid
references), `not_found` (404), `conflict` (409: duplicate unique value), and
`internal_error` (500). Internal database details are logged server-side rather
than sent to clients. Request JSON rejects unknown fields. Route waypoints must
be a non-empty array of `{ "lat": number, "lng": number }` objects. Notification list `limit` must
be 1–100 and `offset` non-negative. Preferences may be partially upserted;
omitted flags default to true on creation and remain unchanged on update.
