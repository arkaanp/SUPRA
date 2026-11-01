# Supra backend: database setup and tests

The tracked application lives here. `supra_db_queries.sql` is a **legacy
reference** containing executable example DML; do **not** run the whole file
against a database. Use only `migrations/` for schema and `seeds/` for optional
demo records. Neither migration nor seeding happens on ordinary server startup.

## Fresh database

Create a PostgreSQL database (local or Supabase). Set `DATABASE_URL` to a
PostgreSQL connection string with permission to create tables and indexes;
keep it in your environment or secret manager, not in Git. From `backend/`:

```sh
export DATABASE_URL='postgres://USER:PASSWORD@HOST:5432/DBNAME'
cargo run --locked -- migrate
cargo run --locked
```

The `migrate` command applies the versioned SQLx migrations and exits. Repeating
it is safe: SQLx records applied versions in `_sqlx_migrations`. Schema changes
should be **new migration files**, never edits to already-applied migrations.
The server requires the schema to exist; it does not apply migrations on startup.

**Populated Supabase projects:** this initial migration uses `IF NOT EXISTS`
and matches the seven-table baseline schema. Back up the database and compare
columns, constraints, indexes, and data to the baseline before running it.
`IF NOT EXISTS` does not detect or repair schema drift. Do not run the legacy
reference file to adopt an existing database. Future changes need additive,
reviewed migrations and compatibility notes.

For an explicitly **disposable/demo** database only, install `psql` and run:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f seeds/demo.sql
```

The seed has stable IDs and is idempotent, but forecast values are illustrative,
not live ML output. Its placeholder password cannot be used for login. Do not
seed a real user or production database.

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

The test applies migrations to this database, exercises user/trip/route/
prediction/preferences/notification handlers and constraints, and cleans up
its fixtures on success. `cargo test` without `-- --ignored` reports it as
ignored; a green unit-only run is **not** a verified database run.
No demo seed is needed for the test. The current endpoints are not authenticated
yet: use only on a private development network until identity/authorization is
implemented.

## API errors and input format

Handler failures return JSON such as `{"error":"Resource not found","code":"not_found"}`.
The codes/statuses are `invalid_request` (400: malformed input or invalid
references), `not_found` (404), `conflict` (409: duplicate unique value), and
`internal_error` (500). Internal database details are logged server-side rather
than sent to clients. Request JSON rejects unknown fields. Route waypoints must
be a non-empty array of `{ "lat": number, "lng": number }` objects; probabilities
and traffic density are numbers between 0 and 1. Notification list `limit` must
be 1–100 and `offset` non-negative. Preferences may be partially upserted;
omitted flags default to true on creation and remain unchanged on update.
