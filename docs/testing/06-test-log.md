# 06 — Test Log

| Field | Value |
|---|---|
| Log ID | `TL-2026-11-09-01` |
| Test cycle | `TC-2026-11-09-01` |
| Branch / commit | `feat/migration-from-prototype` @ `5a5e45d` |
| Host | Linux x86_64 |
| Date | 2026-11-09 |
| Timezone | WIB (UTC+7) |

## 1. Execution summary

| Log entry | Level | Command / action | Result | Evidence |
|---|---|---|---|---|
| `TL-001` | Backend unit | `cargo test --locked --target-dir /tmp/opencode/supra-backend-target` | 32 passed, 1 ignored, 0 failed (33 discovered) | Terminal output; ignored test reported under `TL-002` |
| `TL-002` | Backend integration | Ignored test with `SUPRA_TEST_DATABASE_URL` pointing at a disposable PostgreSQL 18.6 cluster | 1 passed, 0 failed; 32 filtered out | `migrated_schema_enforces_user_boundaries` |
| `TL-003` | Mobile static analysis | `fvm flutter analyze` | No issues found | Terminal output |
| `TL-004` | Mobile unit/widget | `fvm flutter test` | 72 passed, 0 failed | Terminal output |
| `TL-005` | Build — Linux | `fvm flutter build linux` | Success; release bundle produced | `build/linux/x64/release/bundle/supra_mobile_ui` |
| `TL-006` | Build — web | `fvm flutter build web` | Success; web bundle produced | `build/web` |
| `TL-007` | Backend process smoke | Compiled backend + disposable DB; `curl` health/auth/fallback | live 200, ready 200, unauthenticated trips 401, unknown 404 | Sanitized status codes |
| `TL-008` | Full application system | Manual web/Linux flow with approved live account/providers | NOT RUN | Blocked by no approved live test account under the privacy constraint |
| `TL-009` | Layout regression | `fvm flutter test test/layout_16_9_test.dart` | 4 passed after fixing 2 overflows; 0 failed | Home, Assistant, Alerts, Trip at 360×640 |
| `TL-010` | Feedback regression | Focused Home, ML preference, Trip ML, and Assistant context tests | All passed | `display_preferences_test.dart`, `trip_display_preferences_test.dart`, `home_screen_test.dart`, `ai_assistant_test.dart` |

## 2. Detailed entries

### TL-001 — Backend unit tests

- Timestamp: 2026-11-09 11:06 WIB.
- Command:

```sh
cd backend
cargo test --locked --target-dir /tmp/opencode/supra-backend-target
```

- Result:

```text
running 33 tests
...
test result: ok. 32 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out
```

- Ignored test: `db_tests::migrated_schema_enforces_user_boundaries`, because it
  requires `SUPRA_TEST_DATABASE_URL` and a dedicated PostgreSQL `*_test`
  database.
- Notes: no test failures. The ignored case is not counted as a pass.

### TL-002 — Backend integration tests

- Timestamp: 2026-11-09 11:07 WIB.
- Environment: disposable PostgreSQL 18.6 cluster, database name `supra_test`,
  isolated port and Unix socket, trust authentication only for the temporary
  cluster.
- Command pattern:

```sh
SUPRA_TEST_DATABASE_URL="postgres://postgres@localhost:<port>/supra_test?host=<temp-dir>" \
  cargo test --locked --target-dir /tmp/opencode/supra-backend-target -- --ignored
```

- Result:

```text
running 1 test
test db_tests::migrated_schema_enforces_user_boundaries ... ok
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 32 filtered out
```

- Covered behavior: migration application and idempotency, profile isolation,
  trip/route/prediction/notification ownership, cross-user denial, preferences,
  saved places, routines, current-trip finish, alert evaluation queue response,
  and account deletion cleanup.
- Notes: this validates the migration on a fresh database. It does not prove that
  the target application database has the migration applied.

### TL-003 — Flutter analyzer

- Timestamp: 2026-11-09 11:07 WIB.
- Command:

```sh
cd mobile
fvm flutter analyze
```

- Result:

```text
Analyzing mobile...
No issues found! (ran in 10.5s)
```

### TL-004 — Flutter tests

- Timestamp: 2026-11-09 11:07 WIB.
- Command:

```sh
fvm flutter test
```

- Result:

```text
00:05 +72: All tests passed!
```

- Notes: includes login focus regression, Supabase recovery state, map/geocoding,
  conditions freshness, recommendations, trip history, assistant, and home
  forecast/widget tests. The public OpenStreetMap tile warning is informational.

### TL-005 — Linux release build

- Timestamp: 2026-11-09 11:07 WIB.
- Command:

```sh
fvm flutter build linux
```

- Result:

```text
Building Linux application...
✓ Built build/linux/x64/release/bundle/supra_mobile_ui
```

### TL-006 — Web release build

- Timestamp: 2026-11-09 11:08 WIB.
- Command:

```sh
fvm flutter build web
```

- Result:

```text
✓ Built build/web
```

- Notes: Wasm dry run succeeded. Font tree-shaking messages are informational.

### TL-007 — Backend process smoke

- Timestamp: 2026-11-09 11:08 WIB.
- Environment: compiled `backend/target/debug/supra_backend`, isolated
  PostgreSQL 18.6 database, explicit non-production `DATABASE_URL` and
  `SUPABASE_URL` overrides, `ALERTS_ENABLED=false`.
- Result:

| Check | Status |
|---|---|
| `/health/live` | 200 |
| `/health/ready` | 200 |
| `/api/trips` without bearer token | 401 |
| Unknown `/api/does-not-exist` | 404 |

- Notes: the process started and served requests; no live provider or user
  account was used. This is a process-level smoke, not a UI system test.

### TL-008 — Full application system tests

- Status: NOT RUN.
- Reason: the cycle was executed under a privacy constraint that prohibited
  reading or using private configuration, and no approved live test account was
  provided. The recovery email, live providers, and target database migration
  remain environment-owner actions.
- Required before release: execute the P0/P1 system cases in
  [`03-test-cases.md`](03-test-cases.md) and append the results here.

### TL-009 — 16:9 layout regression

- Timestamp: 2026-11-09 (feedback rerun).
- Command:

```sh
cd mobile
fvm flutter test test/layout_16_9_test.dart
```

- Initial result: 2 passed, 2 failed.
  - Assistant app bar `Row` overflowed by 171 px on the right at
    `chat_screen.dart:217` (now a flexible, ellipsized status line).
  - Trip planner overflowed by 100 px on the right at
    `trip_screen.dart:2032` (Trip History title plus sort selector). The first
    fix stacked the header and produced a 22 px vertical overflow; the final fix
    keeps one row and uses icon-only sort segments at narrow widths.
- Final result:

```text
00:01 +4: All tests passed!
```

- Covered: Home, Assistant, Alerts, and Trip at 360×640 logical (720×1280
  physical, DPR 2), including the Home location picker.
- Incident: `INC-006`.

### TL-010 — Feedback-focused regression tests

- Timestamp: 2026-11-09 (feedback rerun).
- Command:

```sh
cd mobile
fvm flutter test test/display_preferences_test.dart
fvm flutter test test/trip_display_preferences_test.dart
fvm flutter test test/home_screen_test.dart
fvm flutter test test/ai_assistant_test.dart
```

- Result:
  - ML preference default/persistence: 2 passed.
  - Trip ML toggle and no-fabrication assertion: 1 passed.
  - Home cards, stale-first indicators, ML toggle, and 16:9 Home: 4 passed.
  - Assistant backend-only/context/scope-related widget assertions: 6 passed.
- Notes: the Trip toggle is only rendered after a route exists; the test injects
  a deterministic OSRM stand-in and confirms the chip reads `ML AQI unavailable`
  when no prediction value is present.

## 3. Rerun log

| Date | Commit | Reason | Result |
|---|---|---|---|
| 2026-11-09 | `42aec46` | Initial automated test cycle | Backend 30/30, DB integration 1/1, Flutter 62/62, analyze clean, builds pass |
| 2026-11-09 | `5a5e45d` | Tester-feedback fixes and regression cases | Backend 32/32, DB integration 1/1, Flutter 72/72, analyze clean, builds pass; layout overflows fixed (`INC-006`) |

## 4. Sanitization statement

This log contains no `.env` contents, `config/local.json` contents, bearer
tokens, provider keys, account emails, project URLs, or personal data. Temporary
database paths and ports are non-sensitive test-environment details. Provider
and database configuration values are referenced only as placeholders.
