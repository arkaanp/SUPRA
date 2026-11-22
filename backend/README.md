# Supra backend: database setup and tests

The tracked application lives here. `supra_db_queries.sql` is a **legacy
reference** containing executable example DML; do **not** run the whole file
against a database. Use only `migrations/` for schema and `seeds/` for optional
demo records. Neither migration nor seeding happens on ordinary server startup.

[Render Free demo deployment guide](../deploy/render/README.md) · [Oracle Cloud Always Free deployment guide](../deploy/oracle/README.md)

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

New registrations supply a username, email and password. On Supabase the signup
trigger reserves the username with the Auth UUID even when email confirmation is
pending. Registration and profile edits accept 3–32 ASCII letters, digits or
underscores. Usernames are stored lowercase. The migration normalizes legacy
names and gives colliding or unusable names a unique UUID-based handle. Existing
users can sign in by email to see or change their handle in Profile.

Email login and recovery use Supabase directly. For username login, configure
`SUPABASE_PUBLISHABLE_KEY` for the same project. Public
`POST /api/auth/username-login` accepts username and password, joins the profile
to the current Auth email by UUID and exchanges credentials with Supabase.
Only a successful password grant for that UUID returns a session. Use HTTPS
and the rate-limited reverse proxy in the deployment guide.

Authenticated `POST /api/users` with `{}` loads or initializes the profile.
Refresh preserves the stored username. `PUT /api/profile` with
`{"username":"new_handle"}` renames it. Protected routes derive ownership from
the verified access token. Release the updated Flutter app with this migration.

## Tests

Automated testing follows unit and integration steps. From the repository root:

```sh
python3 testing/scripts/run_checks.py --stage unit
python3 testing/scripts/run_checks.py --stage integration
```

The Rust partition is declared in `testing/suites.json`. The integration runner
includes local HTTP/JWKS adapters, a new isolated PostgreSQL cluster and the
supplied GTFS feed. It applies migrations, checks authenticated CRUD and
cross-user ownership, and stops the test cluster. It never uses the app database.
The two public Commute API checks are opt-in with `--stage integration --live`.

For a quick mixed Rust-only run from `backend/`, `cargo test --locked` still
works; its total includes both unit and integration cases. It leaves database,
supplied-feed and live-provider cases ignored. A successful mixed run does not
replace the full integration step above.

For a database-only run, use `python3 testing/scripts/run_database_tests.py` from
the repository root. Tests use locally signed JWTs and a local JWKS endpoint,
without a real Supabase account. See [testing/README.md](../testing/README.md)
for prerequisites, fresh results and visible test scripts.

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
while public transit combines the local Transjakarta GTFS feed and Commute Data API.
See [public transport setup](docs/public-transport.md). OTP remains an optional override.

Background alert evaluations can be scheduled by setting `ALERTS_ENABLED=true`.
When enabled, an asynchronous worker evaluates due targets once per minute,
limiting checks to at most once per 5 minutes per target. Publisher news comes from ANTARA RSS through the Python intelligence service;
`NEWS_INCIDENTS_URL` optionally overrides it with a reviewed incident feed. Users can also queue manual checks
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

## Python/PyTorch forecast and publisher news

Start the separate loopback intelligence service before using ML or news checks:
see [ml/README.md](../ml/README.md) for installation, training, startup, model card,
validation and the two testing steps. No new schema migration is needed.
`INTELLIGENCE_URL` defaults to `http://127.0.0.1:8001`. The authenticated
`/api/forecast/hourly` bridge validates model identity, location, horizon and
freshness. News delivery uses the existing in-app notifications table and user
preferences; it is not push delivery.

## Selected-route assistant and news severity

The Gemini assistant now consumes server-fetched route/location conditions,
available PyTorch forecasts and relevant owned publisher reports. Apply the
additive `20261116000000_news_severity_preferences.sql` migration with
`cargo run --locked -- migrate`. Profile/Alerts controls save alert flags and
news severity thresholds. See [the contract](docs/assistant-and-alerts.md) for
payloads, ownership, local-time handling, filters and verification.

## Documented system testing

The third testing stage reviews the supplied screenshots and current notes. See
[the system-test record](../testing/system/README.md) for nine scenario outcomes
and six required changes. These manual results are separate from the automated
runner, and unnoted screenshots are accepted as implemented.
