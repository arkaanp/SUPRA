# Test plan

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Objective and scope

Demonstrate repeatable backend and Flutter checks, visible test source, account
boundaries, trip persistence, routing, conditions, assistant and alerts.
Demo display modes are tested for usability; forecast accuracy is outside this cycle.

## Levels

| Level | Scope | Gate |
|---|---|---|
| Backend unit/router | Validation, JWT/JWKS, errors, provider adapters, alert rules | All executed tests pass |
| Flutter unit/widget | Auth, cache, maps, geocoding, routing, recommendations, Home, chat | All tests pass; analyzer clean |
| Database integration | Migrations twice, CRUD and cross-user isolation | Dedicated disposable *_test database only |
| Process smoke | Health, authentication gate, unknown route | Expected JSON status/code |
| System demo | Real sign-in, account refresh, trips, preferences, recovery and providers | Record each manual outcome |

## Demo acceptance

Automated local checks pass. Before presentation, verify sign-in and account
refresh, confirm and reload a trip, open a map, exercise Home display modes,
ask the assistant a commute question and open Alerts. Record unavailable
provider modes explicitly. The account banner remains an open demo issue until
an authenticated rerun succeeds.

## Dependencies and exclusions

FVM Flutter, Cargo, Python 3; psql for schema inspection. Live recovery callbacks,
OTP/Jakarta GTFS, incident-feed coverage, ML accuracy, push delivery, load and
store packages are outside automated local acceptance. Credentials remain in
ignored local configuration. Do not include personal accounts or tokens in evidence.
