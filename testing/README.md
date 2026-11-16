# SUPRA demo testing

Run from the repository root. Testing documents **unit**, **integration** and **system testing**.
The runner executes the first two stages; supplied system-test evidence is recorded
in [system/README.md](system/README.md). The [00–08 documentation](../docs/testing/00-integration.md)
keeps its existing filenames. Fresh results are in [RESULTS.md](RESULTS.md).

```sh
# Both steps, followed by supporting static analysis
python3 testing/scripts/run_checks.py
# Independently runnable steps
python3 testing/scripts/run_checks.py --stage unit
python3 testing/scripts/run_checks.py --stage integration
```

## Source layout

| Language | Unit testing | Integration testing |
|---|---|---|
| Rust | Inline cases selected by `suites.json` → `unit` | Inline cases selected by `integration`, `database`, `gtfs`, optional `live` |
| Dart/Flutter | `mobile/test/unit/` | `mobile/test/integration/` |
| Python/PyTorch | `testing/python/unit/` | `testing/python/integration/` |

The runner checks every discovered Rust case is classified exactly once. New
Rust tests require a `suites.json` entry. New Dart/Python tests belong in the
matching stage directory; discovery includes them automatically. Mixed HTTP and
isolated tests were split without dropping the existing regression cases.
`fvm flutter test` in `mobile/` still runs both Flutter directories.

## Prerequisites and results

Install Rust/Cargo, FVM/Flutter, PostgreSQL client/server tools (`initdb`, `pg_ctl`,
`createdb`), the ML environment in [ml/README.md](../ml/README.md), and keep the
supplied `file_gtfs/` directory available. The default run needs loopback sockets
and installed dependencies, but no signed-in app, provider keys or demo services.
A missing ML environment or other required dependency fails the run.

Each run writes `testing/evidence/<UTC timestamp>/summary.json` with the tested
commit, working-tree changes, exact commands, per-check counts and exit codes.
Raw logs are divided into `unit/`, `integration/` and supporting checks. Inventory
validation and Flutter analysis are supporting checks and do not add to totals.
An empty or incomplete selected Rust result fails instead of reporting a pass.
The runner continues through independent checks and returns nonzero on failure.

Integration testing creates a new loopback-only PostgreSQL cluster under its
own evidence directory, applies migrations, exercises API ownership/persistence
and stops the cluster. It never connects to the app database. Standalone use:

```sh
python3 testing/scripts/run_database_tests.py
```

Database logs/data remain under `testing/evidence/`. Build output remains in the
package build directories. Checkpoint integration artifacts use `testing/` and
are cleaned after the test. No test code or scripts live in `/tmp`.

## Optional live integrations

```sh
# Public Commute API checks, including Monas–UI bus/KRL alternatives
python3 testing/scripts/run_checks.py --stage integration --live
```

The supplied Transjakarta feed is tested by default; the two public API tests
are opt-in because they depend on network and service-time availability.

The following existing scripts probe running services and are also integration
checks. They are not executed by the default runner and must be recorded
separately before claiming they passed.

| Command under `python3 testing/scripts/` | Purpose / requirements |
|---|---|
| `smoke.py` | Local HTTP health/auth/404 responses |
| `schema_audit.py --backend-env` | Read-only migration/schema metadata; configured DB and `psql` |
| `account_diagnostics.py` | Read-only authenticated account GET timings using existing Linux app session |
| `database_diagnostics.py --backend-env` | Read-only aggregate waits/locks and trigger metadata |
| `provider_freshness.py` | Live weather/CAMS/OpenAQ timestamps and failures |
| `conditions_smoke.py` | Signed-in three-location condition/source check |
| `transit_smoke.py --case monas-ui` | Signed-in route alternatives; does not save trips |
| `intelligence_smoke.py` | Python/backend news and forecast integration; `--evaluate` explicitly queues news for the account |
| `assistant_smoke.py` | Read-only preference queries and one Gemini request; exit 2 reports fallback |
| `alerts_smoke.py` | Read-only inbox preference filtering and mutation-route auth checks |

Probes do not print tokens. Actual alert mutation, read deletion, unread selection
and owner isolation are tested in the disposable DB/client suites. The current
alert widget regressions are in `mobile/test/unit/news_preferences_test.dart`.
Release builds, new manual device executions and model retraining are outside this
documentation update. The default run does not modify the running demo account.

## Screenshot-based system testing

The user supplied 21 screenshots and current notes in `guidelines/system-test/`. Unnoted features are accepted as implemented. Nine scenario groups are recorded: **5 PASS, 3 PARTIAL, 1 FAIL**. Six noted changes remain open. This reviews supplied manual evidence; it does not claim a new interactive execution or change the 152 automated-test total. See [all screenshots and required changes](system/README.md). The runner is unchanged; no new automated test run is claimed for this documentation update.
