# Test procedure

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Prepare

Use the FVM SDK configured by `mobile/.fvmrc`. Install dependencies as described
in the package READMEs. Run from repository root; confirm revision with
`git rev-parse --short HEAD`. Keep private config, account details and keys out
of shared evidence.

## Automated demonstration

```sh
python3 testing/scripts/run_checks.py
```

This runs `cargo test --locked`, `fvm flutter analyze`, and
`fvm flutter test --no-pub`. Logs and summary are saved under
`testing/evidence/<UTC timestamp>/`. Expected baseline: 30 backend passes,
one ignored DB case, 62 Flutter passes, analyzer clean. Inspect failures and
return codes; do not count the ignored database test as a pass.

## Running backend checks

```sh
python3 testing/scripts/smoke.py
python3 testing/scripts/schema_audit.py --backend-env
```

Smoke expects 200/200/401/404 and matching JSON fields. The schema audit is
read-only and shows migration versions and feature columns/tables. Neither
command migrates or restarts the backend.

## Optional database and build checks

Provision a dedicated disposable PostgreSQL database ending in `_test` and set
`SUPRA_TEST_DATABASE_URL` in your shell. Do not point it at the app database.

```sh
python3 testing/scripts/run_checks.py --database
python3 testing/scripts/run_checks.py --builds
```

The runner does not provision or delete databases. Build artifacts stay under
`mobile/build/`; Rust artifacts stay under `backend/target/`.

## Manual demo

1. Launch the app with `--dart-define-from-file=config/local.json` from mobile.
   Ensure `SUPRA_API_URL` is reachable from the device; localhost is device-local.
2. Sign in; retry account refresh. If it fails, record the exact API request,
   status and sanitized backend error. A healthy readiness endpoint is insufficient.
3. Inspect Home conditions, STALE labels, timestamps and the demo display toggle.
4. Plan a car trip; confirm, reload history and finish it. Try walking/motorcycle;
   record transit unavailable if OTP is not configured.
5. Save a place and routine, change preferences, open Alerts and request a check.
6. Ask a commute question; note the observed assistant response/provider status.
7. Check recovery email/code and callbacks with a demo account if configured.
8. Sign out and use another demo account to check isolation.
9. Inspect Home, Trip, Assistant and Alerts at a 360×640 viewport and on the
   presentation device. Record clipping/overflow; no dedicated 16:9 suite is
   present on this main baseline.

Append results to the test log with revision, timestamp, command/case and result.
Generated logs remain local; share only reviewed evidence. No /tmp cleanup or
service termination is performed by the runners.
