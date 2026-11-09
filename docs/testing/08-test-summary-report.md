# 08 — Test Summary Report

| Field | Value |
|---|---|
| Summary ID | `TSR-2026-11-09-01` |
| Test cycle | `TC-2026-11-09-01` |
| Branch / commit | `feat/migration-from-prototype` @ `42aec46` |
| Date | 2026-11-09 |
| Test plan | [`01-test-plan.md`](01-test-plan.md) |
| Test log | [`06-test-log.md`](06-test-log.md) |
| Incident report | [`07-test-incident-report.md`](07-test-incident-report.md) |

## 1. Executive summary

The deterministic local suite is green:

- Backend unit tests: 30 passed, 1 ignored, 0 failed.
- Backend migration/integration test: 1 passed, 0 failed on a disposable
  PostgreSQL 18.6 database; the migrator ran twice successfully.
- Flutter analyzer: no issues.
- Flutter tests: 62 passed, 0 failed.
- Linux and web release builds: both succeeded.
- Compiled backend smoke: live 200, ready 200, unauthenticated protected route
  401, unknown route 404.

The main unresolved product/deployment issue is `INC-001`: the target database
must have `20261109000000_commute_features.sql` applied, otherwise account
refresh and trip confirmation can return HTTP 500. The migration itself was
validated on a fresh disposable database.

Full application system tests (`SY-001`–`SY-010`) were not executed because no
approved live account/provider configuration was used. Live GTFS, verified-news,
ML, and Supabase recovery-email behavior remain unverified.

## 2. Results by level

| Level | Executed | Passed | Failed | Ignored / blocked | Rate |
|---|---:|---:|---:|---:|---:|
| Backend unit | 31 | 30 | 0 | 1 ignored | 100% of executed |
| Backend integration | 1 | 1 | 0 | 0 | 100% |
| Flutter analyzer | 1 | 1 | 0 | 0 | 100% |
| Flutter unit/widget | 62 | 62 | 0 | 0 | 100% |
| Linux build | 1 | 1 | 0 | 0 | 100% |
| Web build | 1 | 1 | 0 | 0 | 100% |
| Backend process smoke | 4 checks | 4 | 0 | 0 | 100% |
| Full application system | 10 planned | 0 | 0 | 10 not run | 0% executed |

The backend unit percentage excludes the ignored database case; that case is
reported separately as the integration result.

## 3. Requirement coverage

| Requirement | Evidence | Status |
|---|---|---|
| Separate temperature, AQI, and weather forecast fields | `UM-010`, `home_screen_test.dart`; `SY-004` planned | Verified at widget level |
| STALE data retains genuine last-known values and timestamps | `UB-007`, `UM-011`, `home_screen_test.dart` | Verified at unit/widget level |
| Password recovery | `UM-002`, `supabase_auth_test.dart`; `SY-003` planned | Model/UI state verified; live email/deep link not run |
| Walking and public-transit modes | `UB-014`, `UB-015`, `UB-020`, `IN-012` | Adapter/stand-in verified; live GTFS not run |
| Mode/packing recommendations | `UM-008`; `SY-005` planned | Rule engine verified; full UI not run |
| Saved places and routines | `IN-008`, `IN-009`; `SY-006` planned | CRUD/isolation mostly verified; UI not run |
| Environmental, traffic, and news alerts | `UB-010`–`UB-013`, `IN-010`; `SY-007` planned | Rules/202 verified; worker/feed/live UI not fully verified |
| Account-scoped backend-confirmed history | `IN-004`, `IN-005`; `SY-005` planned | Ownership/finish verified; mode/geometry assertion partial |
| Backend-only Gemini, no fabrication | `UB-017`, `IN-013` | Verified |
| Avatar validation/storage | `UB-016`, `IN-014`; `SY-008` planned | Backend verified; UI not run |
| Migration applies and is idempotent | `IN-001` | Verified on disposable DB |
| Original regression list | `UM-001`, `UM-012`, `UM-013`, `UM-014`, `UM-016` | Automated regressions pass; packaged Linux UI not repeated |

## 4. Incident summary

| ID | Severity | Status | Effect |
|---|---|---|---|
| `INC-001` | High | Open in target environment | Account refresh/trip confirmation 500 until migration is applied |
| `INC-002` | High | Closed | Forecast compile failure fixed and verified |
| `INC-003` | Low | Closed | Analyzer findings cleared |
| `INC-004` | Low | Closed | Preferences test fixture corrected |
| `INC-005` | Medium | Open — blocked | Live system UI/provider verification not executed |

No critical security or data-loss incident was observed.

## 5. Residual risks

| Risk | Likelihood | Impact | Required action |
|---|---|---|---|
| Target database not migrated | High until confirmed | P0 account/trip failure | Back up, migrate, restart, retest `INC-001` |
| Live GTFS/OTP unavailable or incorrect | High | Transit cannot be trusted | Provision and verify with Jakarta GTFS before enabling |
| Live news feed unavailable or unreviewed | High | News alerts cannot ship | Configure a reviewed feed; verify validation/expiry |
| ML predictions unavailable | Certain | Forecast remains empty | Keep explicit pending/empty state; do not fabricate |
| Supabase recovery email/deep link unverified | Medium | Recovery may fail on real devices | Configure templates/redirect allowlists; run `SY-003` |
| Alert worker/dedup/feed not fully automated | Medium | Duplicate or missed alerts | Add integration tests for claims, dedup, relevance, expiry |
| Places/routines owner update/delete and new notification fields partially asserted | Medium | Regression could slip | Extend the ignored DB test |
| Full UI system tests not run | High | Integration regressions may remain | Execute `SY-001`–`SY-010` in an approved environment |
| Direct Data API RLS not exercised | Low | RLS policy drift | Review policies separately; backend owns application access |

## 6. What the results establish

- The backend compiles, its unit suite passes, and the new migration applies
  cleanly and idempotently to a fresh PostgreSQL database.
- Authenticated ownership boundaries are enforced by the API for the tested
  resources.
- The Flutter client compiles, analyzes cleanly, passes its widget/unit suite,
  and builds for Linux and web.
- The compiled backend starts, connects to a database, serves health checks, and
  rejects unauthenticated protected requests with JSON errors.
- Provider parsing and failure behavior are covered by deterministic stand-ins.

## 7. What the results do not establish

- That the target application database has the new migration applied.
- That live Jakarta public-transit schedules are correct.
- That a live news feed provides sufficient verified coverage.
- That ML predictions exist or are accurate.
- That Supabase recovery emails, redirects, and Android/iOS callbacks work on a
  real device.
- That every screen behaves correctly with real accounts, real providers, and
  real network conditions.
- That the system meets production load or concurrency requirements.

## 8. Release recommendation

**Conditional pass for the deterministic local build; not production-ready yet.**

Recommended gate sequence:

1. Back up and migrate the target database; close `INC-001`.
2. Restart the backend and confirm account refresh and trip confirmation.
3. Execute the P0/P1 system cases with an approved account and configuration.
4. Provision or explicitly defer GTFS, news, ML, and recovery-email verification.
5. Re-run the full automated suite and update this report.

Do not present the application as fully production-ready until the target
migration and live system checks are complete.

## 9. Sign-off

| Role | Decision | Date |
|---|---|---|
| Test executor | Automated local suite accepted; live system gate open | 2026-11-09 |
| Reviewer | Pending | 2026-11-09 |
| Environment owner | Pending migration and live-account approval | 2026-11-09 |
