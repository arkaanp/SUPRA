# 00 — Test Integration

| Field | Value |
|---|---|
| Project | SUPRA — Jakarta commute and environmental assistant |
| Test cycle | `TC-2026-11-09-01` |
| Branch under test | `feat/migration-from-prototype` |
| Application commit | `5a5e45d` |
| Documentation date | 2026-11-09 |
| Platform | Linux x86_64, Flutter 3.47.7, Dart 3.13.5, Rust 1.98.0, PostgreSQL 18.6 |

This document is the entry point for the test documentation set. It explains how
the unit, integration, and system test levels connect, which evidence each level
provides, and which guarantees remain unverified.

## 1. Document map

| Document | Purpose |
|---|---|
| [`01-test-plan.md`](01-test-plan.md) | Scope, objectives, approach, criteria, risks, and deliverables |
| [`02-test-design.md`](02-test-design.md) | Test conditions, techniques, data, environment, and automation design |
| [`03-test-cases.md`](03-test-cases.md) | Case catalog with IDs, expected results, priority, and status |
| [`04-test-procedure.md`](04-test-procedure.md) | Exact setup, execution, cleanup, and recording procedure |
| [`05-test-item-transmittal-report.md`](05-test-item-transmittal-report.md) | Test items delivered, dependencies, and known limitations |
| [`06-test-log.md`](06-test-log.md) | Chronological execution record with sanitized evidence |
| [`07-test-incident-report.md`](07-test-incident-report.md) | Defects, reproduction, root cause, corrective action, and status |
| [`08-test-summary-report.md`](08-test-summary-report.md) | Metrics, coverage, open risks, and release recommendation |

## 2. System under test

```text
Flutter client (Linux / web / mobile)
        |
        | HTTPS + Supabase bearer token
        v
Axum backend (port 3000)
        |
        +--> PostgreSQL / Supabase database
        +--> Supabase Auth (JWKS verification; credentials owned by Supabase)
        +--> Open-Meteo weather, optional BMKG fallback
        +--> OpenAQ PM2.5
        +--> TomTom nearest-road traffic
        +--> Valhalla walking / motorcycle routing
        +--> OpenTripPlanner GTFS GraphQL transit routing (when configured)
        +--> Trusted verified-incident JSON feed (when configured)
        +--> Gemini (server-side only)
```

The test boundary includes the Flutter client, the Axum API, migrations, and the
provider adapters. Supabase Auth, the transit planner, the incident feed, and the
ML prediction service are external dependencies and are tested only where a
deterministic stand-in or explicit unavailability behavior exists.

## 3. Test levels and boundaries

| Level | Target | Boundary | Evidence | Entry criterion | Exit criterion |
|---|---|---|---|---|---|
| Unit — backend | Rust modules, validation, auth, alert rules, routing parsers, provider adapters | No real database; mock HTTP/JWKS where needed | `cargo test --locked` | Code compiles | 0 failures; ignored DB test reported separately |
| Unit — mobile | Models, serializers, recommendation rules, recovery state, map/forecast widgets | No live backend; injected fakes | `fvm flutter test` | Flutter dependencies resolve | 0 failures |
| Integration — backend | Axum handlers + PostgreSQL + migrations | Dedicated disposable `*_test` database; local JWT fixture | `cargo test --locked -- --ignored` | Disposable database reachable | 0 failures; migration applies twice without error |
| Integration — component | Provider adapters and API client against real HTTP stand-ins | Local test HTTP server | Backend unit tests named `real_http_stand_in_*` / `authenticated_http_lookup_*` | Stand-in server starts | Contract and failure cases pass |
| System — backend process | Compiled server, configuration loading, health, auth gate, route fallback | Disposable database; explicit non-production env overrides | `curl` against the running binary | Server starts | Expected status codes observed |
| System — application | Flutter UI + backend + Supabase + providers | Live or staging account and provider configuration | Manual/automated UI run | Test account and configuration approved | P1 flows pass or are explicitly blocked |

## 4. Data and environment flow

1. The database schema is applied explicitly with `cargo run --locked -- migrate`.
   Normal server startup does not migrate.
2. Integration tests create their own identities with a local JWT fixture and a
   mock JWKS endpoint. They do not use a real Supabase account.
3. System tests use the application's configured Supabase project and provider
   configuration. Those values are never copied into this documentation.
4. Provider tests use deterministic HTTP stand-ins for success, timeout,
   malformed, unauthorized, rate-limited, and oversized responses.
5. Live transit, news, ML, and recovery-email behavior is exercised only when
   the corresponding external service is configured and approved.

## 5. Requirement traceability

| Requirement ID | Requirement source | Primary cases | Status |
|---|---|---|---|
| `REQ-FORECAST` | User request: forecast must show temperature, AQI, and weather | `UM-010`, `SY-004` | Unit pass; system not run |
| `REQ-INDICATORS` | Tester feedback: rain/AQI/traffic/temperature indicators must stay visible; missing values say `No data`; aged values say `STALE` | `UM-011`, `UM-017`, `SY-004`, `SY-009` | Unit/widget pass; system not run |
| `REQ-MLTOGGLE` | Tester feedback: future ML predictions are optional and user-selectable on Home and Trip | `UM-018`, `UM-019`, `SY-004`, `SY-005` | Unit/widget pass; live ML source absent |
| `REQ-LAYOUT` | Tester feedback: no overlapping UI at 16:9 phone ratios | `UM-020`, `SY-013` | Widget pass at 360×640; device system run not executed |
| `REQ-STALE` | `guidelines/bugs-and-to-do.md`; genuine last-known data during outages | `UM-011`, `UB-007`, `SY-004` | Unit pass; system not run |
| `REQ-RECOVERY` | Forgot-password option on login and profile | `UM-002`, `UM-015`, `SY-003` | Unit pass; live email/deep link not run |
| `REQ-MODES` | Walking and public transport modes | `UB-014`, `UB-015`, `IN-012`, `SY-005` | Unit/stand-in pass; live GTFS not run |
| `REQ-RECOMMEND` | Mode and packing recommendation from AQI/weather/traffic | `UM-008`, `UM-009`, `SY-005` | Unit pass; UI system not run |
| `REQ-PLACES` | Saved places and routines | `IN-008`, `IN-009`, `SY-006` | Integration partial; UI system not run |
| `REQ-ALERTS` | Environmental, traffic, and relevant news alerts | `UB-010`–`UB-013`, `IN-010`, `IN-017`, `SY-007` | Unit pass; saved-place news evaluation partial; worker/feed/live UI not fully run |
| `REQ-HISTORY` | Account-scoped, backend-confirmed trip history | `IN-004`, `IN-005`, `SY-005` | Integration partial; UI system not run |
| `REQ-GEMINI` | Gemini is backend-only; no fabricated offline answers | `UB-017`, `IN-013` | Pass |
| `REQ-CHAT-CONTEXT` | Gemini receives the last resolved conditions as labelled, untrusted context, including stale status | `UB-022`, `UM-021` | Pass |
| `REQ-CHAT-SCOPE` | Chat politely refuses out-of-scope requests before calling Gemini | `UB-021`, `UM-016` | Pass |
| `REQ-AVATAR` | Validated, ignored, configurable avatar storage | `UB-016`, `IN-014`, `SY-008` | Backend pass; UI system not run |
| `REQ-MIGRATION` | Apply and verify the commute-features migration | `IN-001`, `IN-002` | Pass on disposable database |
| `REQ-REGRESSION` | Original bug list: password focus, map, geocoding, history | `UM-001`, `UM-012`, `UM-013`, `UM-014` | Unit/widget pass; Linux system run not repeated |

## 6. Current status snapshot

| Check | Result | Evidence |
|---|---|---|
| Backend unit tests | 32 passed, 1 ignored, 0 failed (33 discovered) | `06-test-log.md` TL-001 |
| Backend migration/integration test | 1 passed, 0 failed | TL-002 |
| Flutter analyzer | No issues found | TL-003 |
| Flutter tests | 72 passed, 0 failed | TL-004 |
| Linux release build | Success | TL-005 |
| Web release build | Success | TL-006 |
| Backend process smoke | live 200, ready 200, unauthenticated trips 401, unknown route 404 | TL-007 |
| Full application system tests | Not executed — live account/provider configuration not available under the privacy constraint | TL-008 |

The feedback rerun at `5a5e45d` added UI regression cases for stale-first
indicators, the opt-in ML display, 16:9 layout, Gemini condition context, chat
scope enforcement, and saved-place verified news. It also fixed two real 16:9
overflows found by the new layout test (`INC-006`).

## 7. Open gaps and external blockers

| Gap | Impact | Disposition |
|---|---|---|
| Target database migration not confirmed | Account refresh and trip creation can return HTTP 500 until `20261109000000_commute_features.sql` is applied | `INC-001`; validate in the target environment |
| No live OTP GraphQL endpoint / Jakarta GTFS data | Public-transit routes cannot be verified end to end | Marked blocked; adapter contract tested with a stand-in |
| No reviewed `NEWS_INCIDENTS_URL` feed | Verified news alerts cannot be verified end to end | Marked blocked; validation and relevance rules tested |
| No ML prediction source | Forecast values must remain empty; no fabrication is allowed | Accepted limitation; separate temperature/AQI/weather fields are tested |
| Supabase recovery email/redirect/deep-link behavior | Recovery UI and code verification are tested; live email delivery and OS callbacks are not | Manual live check required |
| No live test account in this documentation run | Full UI system flows are not executed | Marked not run; procedure is documented |
| Postman CLI signed out and not initialized | Cloud collection, mock, and workspace publication are unavailable | Local Rust/Dart and HTTP stand-in testing used instead |

## 8. How to read results

- **PASS** means the case was executed and met its expected result.
- **PARTIAL** means related assertions passed but the full case was not exercised.
- **NOT RUN** means the case has not been executed in this cycle.
- **BLOCKED** means an external dependency or approved configuration is missing.
- A green unit run is not a substitute for the ignored database test.
- A green database test is not a substitute for a live system run.

## 9. Secret-handling rule

No `.env` contents, `config/local.json` contents, tokens, keys, account emails,
project URLs, or personal data are recorded in this document set. Commands use
placeholders or process environment variables, and logs are sanitized before
being quoted.
