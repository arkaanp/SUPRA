# Test design

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## 1. Unit testing

Test pure validation, parsers, models, rules and widgets with controlled fixtures.
Use boundary values and state transitions; keep source tests in the packages.

## 2. Integration testing

Backend tests run handlers and adapters with local HTTP/JWKS stand-ins. Flutter
tests use fake clients, injected loaders and widget fixtures. These establish
component behavior; they do not prove live provider availability or complete
runtime failure behavior. Some runtime paths differ from test configuration.

Database integration is opt-in and uses a separate disposable database.
Readiness checks connectivity only; schema inspection checks metadata only.
Neither verifies an authenticated profile/inbox/preferences transaction.

## 3. System testing

Exercise the already running backend through HTTP smoke, then complete the
manual demo on the target device with the configured services. Record account
refresh, trip persistence and user isolation across the full stack. Builds only
establish that packaging succeeds.

## Techniques and data across all three steps

- Boundary values: Jakarta coordinate envelope, weekday/departure/lead limits,
  waypoint counts, payload bounds and environmental rule thresholds.
- State transitions: sign-in/out, recovery, confirmed/finished trips and stale display.
- Negative cases: missing/invalid tokens, cross-user IDs, provider errors,
  malformed payloads, unavailable routes and late geocoding responses.
- Contract checks: JSON models, provider geometry, normalized conditions and errors.
- Cache checks: account/location/village separation and original timestamps using
  injected loaders.

## Main-specific display scope

Home has an opt-in demo ML display using local calculation; this is not a trained
model inference or accuracy test. Preference persistence and a shared Trip toggle
from the docs branch are not delivered by this documentation merge. Dedicated
16:9 regression files from that branch are also absent; assess layout manually.
Assistant credentials are server-side. Provider-failure assertions in backend
unit tests apply to test mode; manually verify the displayed runtime outcome.

## Automation inventory

- `backend/src/db_tests.rs`: ignored database integration.
- Inline Rust test modules in auth, conditions, alerts, mobility, handlers,
  routes and validation.
- `mobile/test/`: authentication, API, conditions/cache, recommendations,
  maps/geocoding, route planner, history, login, Home and assistant tests.
- `testing/scripts/`: suite runner, HTTP smoke and read-only schema inspection.
