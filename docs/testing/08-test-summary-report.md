# Test summary report

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Outcome

**Local automated checks pass; the full authenticated demo remains to be verified.**

| Check | Current result |
|---|---|
| Backend unit/router | 30 passed; one DB test ignored |
| Flutter analyzer | Clean |
| Flutter unit/widget | 62 passed |
| Dedicated DB integration | Not run this cycle |
| HTTP smoke script | PASS: 200/200/401/404 with expected JSON fields |
| Target schema metadata | New trip/notification and commute schema present |
| Linux/web builds | Not rerun this cycle |
| Authenticated user flows | Not run; account warning remains open |

## Demo scope

Auth/recovery, profiles, trips/history, saved places/routines, maps/geocoding,
provider routing, conditions, assistant and inbox features are implemented.
Home includes an opt-in demo prediction display. Trained inference, forecast
accuracy and push delivery are outside this cycle. Public transit needs OTP
and Jakarta GTFS configuration; live incident-feed and recovery behavior need
separate verification.

## Interpretation

Tests exercise component fixtures and stand-ins. Some runtime paths use different
configuration, so passing suites establish their tested boundary rather than
complete live-system behavior. Imported 32/72 counts and build/integration passes
are historical docs-branch results, not main results.

## Before presentation

1. Resolve or reproduce INC-001 with an authenticated request trace.
2. Confirm the device reaches the configured API.
3. Run the visible scripts and retain evidence under `testing/evidence/`.
4. Walk through sign-in, trip persistence, Home display, assistant and inbox.
5. Record unavailable external services and any device layout issues.

No production acceptance or ML accuracy conclusion is made by this demo cycle.
