# 04 — Test Procedure

| Field | Value |
|---|---|
| Procedure ID | `TPR-2026-11-09-01` |
| Test cycle | `TC-2026-11-09-01` |
| Branch / commit | `feat/migration-from-prototype` @ `5a5e45d` |
| Date | 2026-11-09 |

## 1. Safety and privacy rules

1. Do not print or copy `.env`, `config/local.json`, tokens, keys, project URLs,
   account emails, or personal data.
2. Do not run the migration against an application or production database without
   an explicit owner approval and a backup.
3. Use a disposable PostgreSQL cluster for integration tests. Its name must end
   in `_test`.
4. Sanitize command output before pasting it into the test log.
5. Stop disposable services and remove temporary data after the run.

## 2. Prerequisites

| Tool | Purpose |
|---|---|
| Rust / Cargo | Backend build and tests |
| Flutter 3.47.7 / Dart 3.13.5 | Mobile analyze, tests, builds |
| PostgreSQL 18.6 (`initdb`, `pg_ctl`, `createdb`) | Disposable integration database |
| `curl` | Backend process smoke |
| Git | Confirm branch and commit |

Confirm the working tree state before testing:

```sh
git rev-parse --short HEAD
git branch --show-current
git status --short
```

Expected: the commit and branch match the transmittal. Untracked test outputs or
temporary files are disclosed in the log; application behavior is not inferred
from a dirty tree.

## 3. Backend unit tests

```sh
cd backend
cargo test --locked --target-dir /tmp/opencode/supra-backend-target
```

Why a separate target directory: it avoids interfering with a running backend
binary while still using the locked dependency set.

Expected/observed:

- 33 tests discovered.
- 32 passed.
- 1 ignored: `db_tests::migrated_schema_enforces_user_boundaries`.
- 0 failed.

Record the command, timestamp, counts, and any new warnings.

## 4. Backend integration test with a disposable database

Create a fresh cluster, apply the migrations through the ignored test, and stop
the cluster afterward. Use a unique port and data directory to avoid touching
other databases.

```sh
set -euo pipefail
DIR=$(mktemp -d /tmp/opencode/supra-pg-test.XXXXXX)
PORT=55439
cleanup() { pg_ctl -D "$DIR" -m immediate stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

initdb -D "$DIR" -A trust -U postgres >/dev/null
pg_ctl -D "$DIR" -o "-p $PORT -k $DIR" -l "$DIR/server.log" start >/dev/null
createdb -h "$DIR" -p "$PORT" -U postgres supra_test

SUPRA_TEST_DATABASE_URL="postgres://postgres@localhost:$PORT/supra_test?host=$DIR" \
  cargo test --locked --target-dir /tmp/opencode/supra-backend-target -- --ignored
```

Expected/observed:

- 1 test passed: `db_tests::migrated_schema_enforces_user_boundaries`.
- The test applies the migrator twice, so idempotency is exercised.
- 0 failed; 32 filtered out.

The test asserts, among other things:

- profiles are isolated per verified subject;
- trips/routes/predictions/notifications are owner-scoped;
- cross-user updates/deletes return 404;
- preferences defaults and partial updates;
- saved places and routines are owner-scoped;
- current-trip finish is owner-only;
- `POST /api/alerts/evaluate` returns 202 queued;
- account deletion removes owned trips.

## 5. Flutter analyzer and tests

```sh
cd mobile
fvm flutter analyze
fvm flutter test
```

Expected/observed:

- Analyzer: `No issues found!`
- Tests: 72 passed, 0 failed.

If another Flutter command holds the startup lock, wait for it to finish or stop
the unrelated run. Do not kill an active user session without approval.

### 5.1 Focused feedback regression tests

Run these when changing Home indicators, ML display, chat context, or responsive
layout:

```sh
cd mobile
fvm flutter test test/layout_16_9_test.dart
fvm flutter test test/display_preferences_test.dart
fvm flutter test test/trip_display_preferences_test.dart
fvm flutter test test/home_screen_test.dart
fvm flutter test test/ai_assistant_test.dart
```

Expected/observed:

- `layout_16_9_test.dart`: 4 passed (Home, Assistant, Alerts, Trip at 360×640).
- `display_preferences_test.dart`: 2 passed.
- `trip_display_preferences_test.dart`: 1 passed.
- `home_screen_test.dart`: 4 passed, including stale-first indicators and the ML
  toggle.
- `ai_assistant_test.dart`: 6 passed, including labelled condition context.

A layout failure prints the overflowing widget and pixel amount. Fix the widget;
do not delete the assertion or hide the overflow with a clip.

## 6. Release builds

```sh
cd mobile
fvm flutter build linux
fvm flutter build web
```

Expected/observed:

- Linux: `✓ Built build/linux/x64/release/bundle/supra_mobile_ui`.
- Web: `✓ Built build/web` (Wasm dry run succeeded; icon tree-shaking warnings
  are informational).

Build success proves compilation and asset bundling, not runtime behavior.

## 7. Backend process smoke

This starts the compiled backend against an isolated database with explicit
non-production environment overrides. It does not read or print `.env` or
`config/local.json`.

```sh
set -euo pipefail
DIR=$(mktemp -d /tmp/opencode/supra-pg-smoke.XXXXXX)
PORT=55440
cleanup() {
  [ -n "${PID:-}" ] && kill "$PID" >/dev/null 2>&1 || true
  pg_ctl -D "$DIR" -m immediate stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

initdb -D "$DIR" -A trust -U postgres >/dev/null
pg_ctl -D "$DIR" -o "-p $PORT -k $DIR" -l "$DIR/server.log" start >/dev/null
createdb -h "$DIR" -p "$PORT" -U postgres supra_test

export DATABASE_URL="postgres://postgres@localhost:$PORT/supra_test?host=$DIR"
export SUPABASE_URL="https://example.supabase.co"
export ALERTS_ENABLED=false

./target/debug/supra_backend > /tmp/opencode/supra-smoke-backend.log 2>&1 &
PID=$!
for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:3000/health/live >/dev/null 2>&1 && break
  sleep 0.2
done

curl -sS -o /dev/null -w 'live: %{http_code}\n' http://127.0.0.1:3000/health/live
curl -sS -o /dev/null -w 'ready: %{http_code}\n' http://127.0.0.1:3000/health/ready
curl -sS -o /dev/null -w 'unauth trips: %{http_code}\n' http://127.0.0.1:3000/api/trips
curl -sS -o /dev/null -w 'missing: %{http_code}\n' http://127.0.0.1:3000/api/does-not-exist
```

Expected/observed:

| Check | Expected | Observed |
|---|---|---|
| `/health/live` | 200 | 200 |
| `/health/ready` | 200 with reachable DB | 200 |
| `/api/trips` without token | 401 | 401 |
| Unknown `/api/...` | JSON 404 | 404 |

## 8. System UI procedure (manual / approved configuration)

These steps require an approved test account and provider configuration. Do not
record credentials or private endpoints in the log.

1. Start the backend with the approved configuration and the target database
   already migrated.
2. Start the Flutter app on web or Linux with the approved define file. Do not
   print the file contents.
3. Execute the P0/P1 cases in `03-test-cases.md`:
   - `SY-001` startup;
   - `SY-002` sign-in/out;
   - `SY-003` recovery;
   - `SY-004` home forecast, stale indicators, and ML toggle;
   - `SY-005` trip planning, ML display, and history;
   - `SY-006` places/routines;
   - `SY-007` alerts and saved-place news;
   - `SY-009` offline/provider outage;
   - `SY-013` phone layout at 16:9;
   - `SY-014` chat scope and condition context.
4. For each case, record pass/fail, the visible message, and a sanitized
   screenshot or note.
5. When testing the ML toggle, leave it off first and confirm no numeric future
   prediction appears. Enable it and confirm any missing model output is labelled
   unavailable, not invented.
6. When testing stale data, keep the app open across a provider outage and
   confirm original observation times remain unchanged and every affected
   indicator says `STALE`.
7. If a flow is blocked, record the missing dependency and stop; do not
   substitute invented data.

### 8.1 Target-database migration check for `INC-001`

Before retrying account refresh or trip confirmation in the target environment:

1. Confirm the database is backed up.
2. Confirm the owner approved the migration.
3. Run from `backend/`:

```sh
cargo run --locked -- migrate
```

4. Confirm the migration version `20261109000000` is present in
   `_sqlx_migrations` (query through the approved database client; do not print
   the connection string).
5. Restart the backend so it uses the current schema.
6. Sign in again and confirm:
   - the account banner does not appear;
   - `POST /api/trips` succeeds;
   - no `Internal server error` appears.

If the 500 persists, capture the backend `tracing` error for the exact SQL
failure, sanitize it, and reopen `INC-001`.

## 9. Recording results

For every run, append to `06-test-log.md`:

- log ID and timestamp;
- test level and case IDs;
- command (sanitized);
- environment (OS, toolchain, database type, commit);
- counts and result;
- evidence location;
- deviation/incident ID.

Raise an incident in `07-test-incident-report.md` when actual behavior differs
from expected, a test is blocked by a product defect, or a rerun changes a
previously passing result.

## 10. Cleanup

- Stop the disposable PostgreSQL cluster.
- Stop the backend process.
- Remove temporary directories under `/tmp/opencode/` when no longer needed.
- Do not remove user uploads or unrelated files.
- Confirm no test process remains on port 3000.

## 11. Rerun checklist

- [ ] `cargo test --locked` green.
- [ ] Ignored database test green on a fresh `*_test` database.
- [ ] `fvm flutter analyze` clean.
- [ ] `fvm flutter test` green.
- [ ] `fvm flutter test test/layout_16_9_test.dart` green on all four screens.
- [ ] ML display is off by default, persists when enabled, and never fabricates.
- [ ] Stale indicators retain original timestamps and show `STALE`.
- [ ] Chat scope guard refuses out-of-scope requests without a provider call.
- [ ] Saved-place verified-news evaluation is checked with a reviewed feed or accepted as blocked.
- [ ] Linux build succeeds.
- [ ] Web build succeeds.
- [ ] Backend smoke returns 200/200/401/404.
- [ ] Target database migration confirmed or `INC-001` accepted as a deployment gate.
- [ ] No secrets in the log, incident report, or summary.
