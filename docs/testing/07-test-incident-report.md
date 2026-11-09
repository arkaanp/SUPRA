# 07 — Test Incident Report

| Field | Value |
|---|---|
| Report ID | `TIR-2026-11-09-01` |
| Test cycle | `TC-2026-11-09-01` |
| Branch / commit | `feat/migration-from-prototype` @ `42aec46` |
| Date | 2026-11-09 |

## 1. Incident summary

| ID | Title | Severity | Status |
|---|---|---|---|
| `INC-001` | Account refresh and trip confirmation return HTTP 500 after schema change | High | Open in target environment; migration validated on disposable DB |
| `INC-002` | Flutter compile failure in forecast weather-code switch | High | Closed — verified by analyzer, tests, and builds |
| `INC-003` | Analyzer brace/final-field findings | Low | Closed — analyzer clean |
| `INC-004` | Preferences serialization test expected the old three-key JSON | Low | Closed — test passes |
| `INC-005` | Full application system verification blocked | Medium | Open — blocked by unapproved live account/providers |

## 2. INC-001 — Account refresh and trip confirmation HTTP 500

| Field | Value |
|---|---|
| Severity | High |
| Priority | P0 |
| Status | Open in the target environment; fix validated on a disposable database |
| Detected by | User report: “Account refresh unavailable” banner and “Internal server error” on trip actions |
| Environment | Backend at `42aec46` against a database without the commute-features migration |
| Related cases | `IN-001`, `IN-002`, `SY-001`, `SY-005` |

### Description

`loadAccount()` calls `POST /api/users`, `GET /api/trips`,
`GET /api/users/{id}/notifications`, and `PUT /api/users/{id}/preferences`.
The backend maps these responses into Rust structs that now include fields added
by `20261109000000_commute_features.sql`. If those columns are absent, SQLx
fails to decode the row, `AppError::Internal` returns HTTP 500
`{"error":"Internal server error"}`, and the client shows the account banner.

Confirming or starting a trip calls `POST /api/trips`, whose `INSERT` references
`transport_mode`, `active_until`, and `route_waypoints`. The same schema drift is
the leading explanation for the 500 and the snackbar “Trip could not be saved:
Internal server error.” The exact endpoint and backend log line must be captured
to confirm it.

### Reproduction steps

1. Use a database that has migrations only through `20261108000001`.
2. Start the backend from commit `42aec46`.
3. Sign in and load the account.
4. Observe the “Account refresh unavailable” banner.
5. Select a route and confirm/start the trip.
6. Observe the 500 message.

### Expected

- Account data loads without an error banner.
- A confirmed trip is persisted and returned.
- No 500 appears for valid input.

### Actual

- Account refresh fails with HTTP 500.
- Trip confirmation fails with HTTP 500.

### Evidence

- `backend/src/handlers/trips.rs` uses `SELECT *` / `RETURNING *` with the new
  trip fields.
- `backend/src/handlers/notification_preferences.rs` and
  `backend/src/handlers/notifications.rs` use `SELECT *` / `RETURNING *` with the
  new preference and notification fields.
- `backend/src/error.rs` maps internal SQL errors to the sanitized
  “Internal server error” response.
- `backend/src/main.rs` does not run migrations during ordinary startup.
- `IN-001` on a disposable database passes, proving the migration itself applies
  cleanly and is idempotent.

Note: selecting a **car** history item uses OSRM and would not return the backend
JSON error. Selecting a **walk/motorcycle/transit** item calls
`/api/mobility/plan`, which returns 503 when unconfigured, not 500. The 500 is
therefore most consistent with account loading or trip persistence.

### Root cause

Schema drift: the target database has not had
`20261109000000_commute_features.sql` applied while the backend code expects its
columns.

### Corrective action

1. Back up the target database.
2. Obtain owner approval.
3. Run:

```sh
cd backend
cargo run --locked -- migrate
```

4. Confirm version `20261109000000` is recorded in `_sqlx_migrations`.
5. Restart the backend.
6. Retry account refresh and trip confirmation.

### Verification performed

- The migration applied successfully to a fresh disposable PostgreSQL 18.6
  database and a second run was idempotent (`IN-001`).
- The authenticated integration test passed, including profile/trip/place/routine
  ownership and the queued alert endpoint (`TL-002`).

### Closure criteria

- Target database records the migration.
- Account refresh succeeds without the banner.
- Trip confirmation succeeds without a 500.
- The backend log shows no relevant SQL decode error.

### Regression coverage

`IN-001`, `IN-002`, `IN-005`, and `SY-005`.

## 3. INC-002 — Flutter compile failure in forecast weather-code switch

| Field | Value |
|---|---|
| Severity | High |
| Priority | P0 |
| Status | Closed |
| Detected by | `fvm flutter test` compile failure |
| Environment | Flutter/Dart at the test commit |

### Description

The forecast helper switched on a nullable `int?` weather code and used
relational patterns such as `>= 51`. Dart rejected the relational operators on a
nullable receiver, so the mobile test suite could not compile.

### Expected

The forecast helper compiles and maps WMO weather codes to text/icons.

### Actual

Compilation errors:

```text
The method '>=' isn't defined for the type 'int?'.
The method '<=' isn't defined for the type 'int?'.
```

### Root cause

Relational patterns were applied to a nullable value.

### Corrective action

Switch on `code ?? -1`, preserving constant and range patterns on a non-null
integer.

### Verification

- `fvm flutter analyze`: no issues.
- `fvm flutter test`: 62 passed.
- `fvm flutter build linux`: success.
- `fvm flutter build web`: success.

### Regression coverage

`UM-010`, `UM-011`, `SY-004`, `SY-011`.

## 4. INC-003 — Analyzer brace/final-field findings

| Field | Value |
|---|---|
| Severity | Low |
| Priority | P2 |
| Status | Closed |
| Detected by | `fvm flutter analyze` |
| Environment | Flutter/Dart at the test commit |

### Description

Analyzer reported four informational findings after the feature edits:
`curly_braces_in_flow_control_structures` in several files and
`prefer_final_fields` for the routine weekday set.

### Corrective action

Added braces and made the field final where appropriate; formatting was applied
across touched Dart files.

### Verification

Current `fvm flutter analyze` reports `No issues found!`.

### Regression coverage

`TL-003`.

## 5. INC-004 — Preferences serialization test expected old JSON

| Field | Value |
|---|---|
| Severity | Low |
| Priority | P2 |
| Status | Closed |
| Detected by | `fvm flutter test` |
| Environment | Flutter test suite |

### Description

`NotificationPreference.toJson()` now includes `alert_relevant_news`, but the
test fixture expected only the original three keys.

### Corrective action

Updated the fixture to include the news flag.

### Verification

`mobile/test/backend_api_test.dart` passes; the full Flutter suite reports 62
passed.

### Regression coverage

`UM-003`.

## 6. INC-005 — Full application system verification blocked

| Field | Value |
|---|---|
| Severity | Medium |
| Priority | P1 |
| Status | Open — blocked |
| Detected by | Test planning and environment review |
| Environment | This test cycle |

### Description

The full UI system cases (`SY-001`–`SY-010`) were not executed. The cycle was
run under a constraint not to read or use private configuration, and no approved
live test account was supplied. Live transit, news, ML, and recovery-email
services are also not provisioned in this environment.

### Impact

Local unit, integration, build, and process-level evidence is strong, but the
following remain unverified end to end:

- Supabase recovery email delivery, redirect allowlist, and Android/iOS callback
  behavior.
- Live GTFS/OTP public-transit itineraries.
- Live verified-news alerts and source links.
- Live provider rate limits and outage behavior in the UI.
- Linux desktop map rendering in the packaged application.
- Full account-scoped history and alert flows through the UI.

### Required action

Use an approved staging/test account and provider configuration, then execute
the P0/P1 system cases. Record results in `06-test-log.md` and update this
incident.

### Closure criteria

- `SY-001`–`SY-010` executed and pass, or each blocked case has an approved
  disposition.
- Live recovery, transit, news, and ML limitations are explicitly accepted or
  provisioned.

## 7. Incident severity definitions

| Severity | Meaning |
|---|---|
| Critical | Data loss, security breach, or complete inability to use the product |
| High | Core flow blocked or incorrect safety/environmental advice |
| Medium | Important flow degraded or significant verification gap |
| Low | Cosmetic, diagnostic, or non-blocking test/documentation issue |

## 8. Status summary

- Closed: `INC-002`, `INC-003`, `INC-004`.
- Open product/deployment issue: `INC-001`.
- Open verification gap: `INC-005`.
- No critical security or data-loss incident was observed in this cycle.
