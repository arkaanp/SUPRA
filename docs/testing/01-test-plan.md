# Test plan

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Objective and scope

Demonstrate repeatable backend and Flutter checks, visible test source, account
boundaries, trip persistence, routing, conditions, assistant and alerts.
Demo display modes are tested for usability; forecast accuracy is outside this cycle.

## Three testing steps

### 1. Unit testing

Check validation, parsers, model serialization, scheduling/recommendation rules,
cache state and widgets in isolation. Flutter analysis is a supporting check.
Exit: all executed unit assertions pass and analysis is clean.

### 2. Integration testing

Check router/auth/provider interactions with local HTTP/JWKS stand-ins and API
client contracts. Run database migrations twice, CRUD and ownership assertions
against a dedicated disposable `*_test` database. Schema metadata is supporting
evidence only. Exit: component and dedicated database assertions pass; record
missing environments as NOT RUN rather than treating unit results as a substitute.

### 3. System testing

Check the running backend with HTTP smoke, then sign-in, account refresh, trips,
preferences, recovery, conditions, assistant and alerts in the complete app.
Builds are preparation, not end-to-end evidence. Exit: smoke checks and required
manual demo cases pass or have an explicitly recorded limitation.

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
