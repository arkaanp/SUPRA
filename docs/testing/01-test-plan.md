# 01 — Test plan

## Objective and scope

Rerun the current demo's tests in two steps: **unit testing**, followed by
**integration testing**. Keep all nine documentation filenames, make test code
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

The runner must exit nonzero for failed checks. Static analysis must be clean.
Public-provider integrations are opt-in and reported separately when not run.
Release builds, device walkthroughs and model retraining are outside this cycle.
No test may use the demo application's database for destructive assertions.
