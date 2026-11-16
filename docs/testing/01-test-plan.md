# 01 — Test plan

## Objective and scope

Document the demo in three steps: **unit testing**, **integration testing**,
and **system testing**. Keep all nine documentation filenames, make test code
and runners visible in the repository, and record fresh stage-specific evidence.

Coverage includes authentication and account boundaries, trip/route models,
map/environment conditions and freshness, transit alternatives, alert filtering
and read-state controls, assistant grounding, publisher news, and ML input/output
contracts. Existing automated regression coverage is retained during the split.

## Prerequisites

- Rust/Cargo and locked backend dependencies.
- FVM and the project's configured Flutter SDK; dependencies installed in `mobile/`.
- `ml/.venv/bin/python` with `ml/requirements.txt` installed, including PyTorch.
- PostgreSQL tools `initdb`, `pg_ctl`, `createdb`, available on `PATH`; run as a
  normal user rather than PostgreSQL-disallowed root.
- The supplied `file_gtfs/` feed for the full integration step.
- Permission to bind loopback sockets and access local SDK/build caches.

The default run uses local dependencies and provider responses controlled by the
tests. It requires no app session, provider API keys or running demo services.
Missing tools, environment, feed or failing assertions fail the run.

## Acceptance

1. Unit testing passes independently, with nonempty Rust, Flutter and Python suites.
2. Integration testing passes independently, including migrated PostgreSQL and
   supplied-feed checks, with no overlap in Rust test classification.
3. System acceptance requires closing the six noted change items and recording retests.
   Supplied unnoted screenshot states are accepted as implemented.

The runner must exit nonzero for failed checks. Static analysis must be clean.
Public-provider integrations are opt-in and reported separately when not run.
Release builds, new interactive device executions and model retraining are outside this update.
No test may use the demo application's database for destructive assertions.

## System evidence scope

The user supplied 21 screenshots and current notes in `guidelines/system-test/`. Unnoted features are accepted as implemented. Nine scenario groups are recorded: **5 PASS, 3 PARTIAL, 1 FAIL**. Six noted changes remain open. This reviews supplied manual evidence; it does not claim a new interactive execution or change the 152 automated-test total. The screenshot index defines expected changes and retest criteria; see [system evidence and screenshots](../../testing/system/README.md).
