# 01 — Test Plan

| Field | Value |
|---|---|
| Test plan ID | `TP-2026-11-09-01` |
| Project | SUPRA |
| Test cycle | `TC-2026-11-09-01` |
| Branch / commit | `feat/migration-from-prototype` @ `42aec46` |
| Plan date | 2026-11-09 |
| Related documents | [`00-integration.md`](00-integration.md), [`02-test-design.md`](02-test-design.md), [`03-test-cases.md`](03-test-cases.md) |

## 1. Introduction

This plan defines how SUPRA is verified across unit, integration, and system
levels. It covers the backend API, database migrations, Flutter client, provider
adapters, and the main user flows added for password recovery, saved places and
routines, walking/transit modes, recommendations, alerts, and the three-field
forecast.

The plan deliberately separates deterministic local evidence from live provider
evidence. A passing local run proves contract and regression behavior; it does
not prove that a live GTFS feed, news feed, Supabase recovery email, or ML
prediction source is configured.

## 2. Test items

| Item | Location | Version / identifier |
|---|---|---|
| Backend source | `backend/src` | Commit `42aec46` |
| Database migrations | `backend/migrations` | Includes `20261109000000_commute_features.sql` |
| Mobile source | `mobile/lib` | Commit `42aec46` |
| Backend unit/integration tests | `backend/src/**/*.rs` | Commit `42aec46` |
| Flutter tests | `mobile/test` | Commit `42aec46` |
| Feature contracts | `backend/docs/commute-features.md`, `backend/docs/current-conditions.md` | Commit `42aec46` |
| Requirements and bug list | `guidelines/bugs-and-to-do.md` | Working copy |

## 3. Features to be tested

1. Supabase sign-in, sign-out, session handling, profile creation, and password
   recovery by email code and recovery session.
2. Current conditions: independent weather, air-quality, and traffic signals;
   stale readings retained with original timestamps; partial provider failure.
3. Forecast strip: separate temperature, AQI, and weather fields; explicit
   pending state for future ML output; no fabricated values.
4. Trip planning: car, motorcycle, walking, and public-transit selection;
   provider geometry, duration, distance, and provenance.
5. Route recommendations: duration plus fresh PM2.5/rain preferences; stale or
   missing values do not establish current risk; packing and exposure advice.
6. Saved places and routines: CRUD, ownership, validation, scheduling fields,
   timezone, lead time, and alert/news subscriptions.
7. Trip history: backend-confirmed events only, account scoping, mode
   persistence, current-trip alerts, and finish behavior.
8. Alerts: due-window calculation, freshness rules, deduplication, manual
   evaluation, background worker, incident-feed validation, relevance, and
   expiry.
9. Avatar upload: content validation, size/dimension bounds, PNG re-encoding,
   public serving, and account-scoped cleanup.
10. Original regressions: password field focus, Linux map rendering, explicit
    geocoding selection, backend-only Gemini, and honest empty states.

## 4. Features not to be tested in this cycle

- Live Jakarta GTFS schedule accuracy and real-time transit arrivals.
- Live news incident coverage beyond a reviewed, configured feed.
- ML prediction accuracy, model training, or future-value quality.
- Production load, stress, soak, or capacity testing.
- Payment, billing, or third-party account provisioning.
- App-store packaging, signing, and mobile device distribution.
- Direct Data API access through Supabase roles (the backend uses a server-only
  role that bypasses RLS; application ownership checks are tested instead).

These items are excluded because they require external data, production
credentials, hardware, or a separate performance environment. Their absence is
recorded as a residual risk, not as a pass.

## 5. Test approach

### 5.1 Unit testing

- Rust: exercise pure rules, validation, parsing, error mapping, auth claims,
  provider failure classification, alert timing, and freshness.
- Flutter: exercise models, serializers, widget states, recommendation rules,
  route mode values, recovery state, and map/forecast rendering with injected
  fakes.
- Unit tests must not require a live database, live Supabase project, or live
  provider API.

### 5.2 Integration testing

- Apply all SQLx migrations to a dedicated disposable PostgreSQL database whose
  name ends in `_test`.
- Exercise authenticated CRUD and ownership boundaries through the Axum router.
- Verify migration idempotency by running the migrator twice.
- Use local JWT fixtures and a mock JWKS endpoint; never a real user account.
- Use local HTTP stand-ins for provider success and failure contracts.

### 5.3 System testing

- Start the compiled backend against an isolated database and verify health,
  readiness, authentication gating, and JSON fallbacks.
- Run the Flutter application against the backend and configured Supabase
  project for approved manual flows.
- Execute the P1 flows in [`03-test-cases.md`](03-test-cases.md): sign-in,
  recovery, home forecast, trip planning, saved places/routines, alerts, and
  profile.
- Record blocked flows with the exact missing dependency.

### 5.4 Regression testing

Every original bug in `guidelines/bugs-and-to-do.md` has at least one unit,
widget, or integration case. The regression set is rerun before release.

## 6. Pass/fail criteria

### 6.1 Level exit criteria

| Level | Pass criteria |
|---|---|
| Backend unit | 0 failed tests; ignored database test reported separately |
| Backend integration | 0 failed tests; migration applies to a fresh `*_test` database and a second run is idempotent |
| Flutter unit/widget | 0 failed tests; analyzer reports no issues |
| Build | Linux release bundle and web release build both succeed |
| Backend process smoke | `/health/live` 200, `/health/ready` 200 with a reachable DB, unauthenticated protected route 401, unknown route JSON 404 |
| System | All P1 cases pass, or are explicitly blocked with an approved external dependency |

### 6.2 Cycle exit criteria

- No open critical or high-severity defect in the test environment.
- `INC-001` (target-database schema drift) is closed or explicitly accepted with
  a deployment gate.
- Test log, incident report, and summary report are complete.
- No secret, token, account email, or private configuration value appears in any
  test artifact.
- Residual risks and blocked live checks are listed in the summary.

## 7. Suspension and resumption

Testing is suspended when:

- the database is unreachable or a migration fails unexpectedly;
- the Flutter toolchain is locked by another long-running command;
- a required provider is unavailable in a way that prevents a deterministic
  outcome;
- a P0 build failure prevents the suite from starting;
- executing a test would require exposing a secret or using an unapproved
  production account.

Testing resumes when the blocking condition is removed, the environment is
recorded, and the affected cases are rerun from a clean state.

## 8. Test environment

| Component | Requirement |
|---|---|
| OS | Linux x86_64 |
| Rust | Stable toolchain capable of building the locked dependency set |
| Flutter | 3.47.7 stable / Dart 3.13.5 as used in this cycle |
| PostgreSQL | 18.6 disposable cluster for integration tests |
| Backend runtime | Axum server on port 3000 |
| Supabase | Configured project for live auth; not required for unit/integration |
| Providers | Optional per test; missing configuration must produce explicit unavailable states |
| Browser/desktop | Flutter web-server or Linux desktop for system flows |

Environment values are supplied to processes outside this document. The
documentation records only the variable names and placeholders.

## 9. Test data

- Synthetic Supabase subject UUIDs and locally signed JWTs for integration.
- Greater Jakarta coordinates inside the accepted service envelope.
- Boundary coordinates outside the envelope for negative tests.
- Synthetic PM2.5 values below, at, and above the 35.5 µg/m³ advisory threshold.
- Synthetic precipitation below, at, and above the 1.0 mm and 0.2 mm thresholds.
- Synthetic traffic speeds with confidence below and above 0.5.
- Weekday/time combinations including Sunday 23:50 WIB and Monday 00:10 WIB.
- Synthetic incident records with valid HTTPS source links, expired records,
  unverified records, and out-of-area coordinates.
- Synthetic route geometry with valid and deliberately broken polylines.

No production user data is copied into test fixtures.

## 10. Schedule

| Phase | Order |
|---|---|
| Preparation | Confirm toolchains, disposable database, and build access |
| Unit | Backend then Flutter |
| Integration | Migrations and authenticated API tests |
| Build | Linux and web release builds |
| System | Backend process smoke, then approved UI flows |
| Reporting | Log, incidents, summary, and release recommendation |

## 11. Risks and contingencies

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Target database lacks the new migration | High until confirmed | Account and trip requests return 500 | Back up, run `cargo run --locked -- migrate`, retry, record in `INC-001` |
| Live OTP/GTFS unavailable | High | Transit flow cannot be verified end to end | Contract-test the adapter; mark system case blocked |
| News feed unavailable | High | Verified news alerts cannot be verified | Validate feed rules with synthetic records; mark live case blocked |
| ML source unavailable | Certain | Forecast values remain empty | Treat empty values as correct; no fabrication |
| Supabase recovery email/deep link untested | Medium | Recovery may fail on a real device | Manual live check with approved account |
| Flutter startup lock | Medium | Test commands wait or fail | Serialize Flutter commands; rerun after the lock clears |
| Provider rate limits | Medium | Route/condition calls fail | Use stand-ins for deterministic tests; respect documented limits |
| Sensitive data in logs | Low | Privacy/security incident | Sanitize logs; never print env/config contents |

## 12. Roles and responsibilities

| Role | Responsibility |
|---|---|
| Implementer | Provides buildable items, migrations, and deterministic tests |
| Test executor | Runs the procedure, records results, raises incidents |
| Reviewer | Checks traceability, severity, and release recommendation |
| Environment owner | Approves database migration and live provider/account use |

## 13. Deliverables

- This plan.
- Test design and case catalog.
- Execution procedure.
- Test item transmittal report.
- Test log with sanitized evidence.
- Incident report.
- Test summary report with a release recommendation.

## 14. Approval

| Role | Name / decision | Date |
|---|---|---|
| Test executor | Pending | 2026-11-09 |
| Reviewer | Pending | 2026-11-09 |
| Environment owner | Pending | 2026-11-09 |
