# 05 — Test Item Transmittal Report

| Field | Value |
|---|---|
| Transmittal ID | `TITR-2026-11-09-01` |
| Test cycle | `TC-2026-11-09-01` |
| From | Implementation / build owner |
| To | Test executor / reviewer |
| Date | 2026-11-09 |
| Branch | `feat/migration-from-prototype` |
| Commit under test | `42aec46` |
| Related plan | [`01-test-plan.md`](01-test-plan.md) |

## 1. Purpose

This report identifies the items delivered for testing, their provenance, the
configuration placeholders required to run them, and the limitations that affect
what the test results can establish.

## 2. Delivered items

| Item ID | Item | Location | Version / note |
|---|---|---|---|
| `TI-001` | Backend application source | `backend/src` | Commit `42aec46` |
| `TI-002` | Database migrations | `backend/migrations` | Includes `20261109000000_commute_features.sql` |
| `TI-003` | Backend unit and integration tests | `backend/src/**/*.rs` | Commit `42aec46` |
| `TI-004` | Mobile application source | `mobile/lib` | Commit `42aec46` |
| `TI-005` | Mobile tests | `mobile/test` | Commit `42aec46` |
| `TI-006` | Feature contracts | `backend/docs/commute-features.md`, `backend/docs/current-conditions.md` | Commit `42aec46` |
| `TI-007` | Test documentation set | `docs/testing` | This cycle |
| `TI-008` | Linux release bundle | `mobile/build/linux/x64/release/bundle/supra_mobile_ui` | Built in this cycle |
| `TI-009` | Web release bundle | `mobile/build/web` | Built in this cycle |

## 3. Changes relevant to testing

- Forecast tiles expose temperature, AQI, and weather as separate fields.
- Password recovery supports email request, code verification, and password
  update, with recovery-session handling.
- Saved places, routines, walking mode, and public-transit mode are present.
- Recommendation rules use fresh PM2.5/AQI, rain, and nearest-road congestion as
  preferences without changing provider ETA.
- Alerts include manual queued evaluation, freshness rules, deduplication,
  source links, and expiry.
- Trips persist transport mode and optional route geometry; current-trip alerts
  can be finished without deleting history.
- The commute-features migration adds the supporting columns and tables.

## 4. Configuration placeholders

The following are required only for the indicated test level. Values are supplied
outside this document.

| Placeholder | Needed by | Purpose |
|---|---|---|
| `<DATABASE_URL>` | Backend runtime | Application database |
| `<SUPABASE_URL>` | Backend runtime | JWKS issuer |
| `<SUPABASE_JWT_AUDIENCE>` | Backend runtime | Token audience, default `authenticated` |
| `<SUPRA_TEST_DATABASE_URL>` | Integration test | Disposable `*_test` database |
| `<OPENAQ_API_KEY>` | Conditions | PM2.5 provider |
| `<TOMTOM_API_KEY>` | Conditions | Nearest-road traffic |
| `<VALHALLA_ROUTE_URL>` | Mobility | Walking/motorcycle routing |
| `<OTP_GRAPHQL_URL>` | Mobility | Public-transit GTFS planner |
| `<NEWS_INCIDENTS_URL>` | Alerts | Verified incident feed |
| `<GEMINI_API_KEY>` / `<GEMINI_MODEL>` | Assistant | Server-side model configuration |
| `<AVATAR_STORAGE_DIR>` | Avatar | Runtime upload directory |
| `<PUBLIC_BASE_URL>` | Avatar | Public origin for stored images |
| `<RECOVERY_REDIRECT_URL>` | Recovery | Supabase recovery redirect allowlist |

No values are recorded here.

## 5. Build and test evidence

| Evidence | Result |
|---|---|
| Backend unit run | 30 passed, 1 ignored, 0 failed |
| Backend integration run | 1 passed, 0 failed on disposable PostgreSQL 18.6 |
| Flutter analyzer | No issues found |
| Flutter tests | 62 passed, 0 failed |
| Linux build | Success |
| Web build | Success |
| Backend process smoke | live 200, ready 200, unauthenticated 401, unknown 404 |

Detailed evidence is in [`06-test-log.md`](06-test-log.md).

## 6. Known limitations and external dependencies

| Limitation | Effect on testing |
|---|---|
| Target database may not have `20261109000000_commute_features.sql` applied | Account refresh and trip confirmation can return 500; see `INC-001` |
| No live OTP GraphQL endpoint or licensed Jakarta GTFS data | Public-transit system flow cannot be verified end to end |
| No reviewed `NEWS_INCIDENTS_URL` feed | Live verified-news alerts cannot be verified end to end |
| No ML prediction source | Forecast values remain empty by design; no accuracy claim |
| Recovery email/redirect/deep-link configuration not verified live | Recovery model and UI paths are tested; live delivery is not |
| No approved live test account in this cycle | Full application system tests are not run |
| Postman CLI signed out/uninitialized | Cloud collection/mock/workspace tests unavailable |

## 7. Items explicitly not delivered

- Production or staging credentials.
- Jakarta GTFS data or a hosted OTP deployment.
- A verified news incident feed.
- An ML model, training data, or prediction service.
- Mobile app-store packages or signing material.
- A load/performance environment.

## 8. Acceptance for testing

| Role | Name / decision | Date |
|---|---|---|
| Build owner | Delivered for local test | 2026-11-09 |
| Test executor | Accepted with the limitations above | 2026-11-09 |
| Reviewer | Pending | 2026-11-09 |

Testing may proceed on the deterministic local layers immediately. Live system
testing requires the environment owner to approve an account, database migration,
and provider configuration.
