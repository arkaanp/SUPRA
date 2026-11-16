# 05 — Test item transmittal report

## Revision

Application baseline: `e6627b5` on `feat/ai-integration`.
This cycle changes test organization, runners and documentation in the working
tree; it does not change app behavior or train a new forecast model.
The exact tested revision and local changes are saved with execution evidence.

## Delivered assets

| Item | Location | Purpose |
|---|---|---|
| Unit tests | `mobile/test/unit/`, `testing/python/unit/`, Rust module cases | Isolated regression assertions |
| Integration tests | `mobile/test/integration/`, `testing/python/integration/`, Rust module cases | HTTP/client, provider, persistence and artifact contracts |
| Rust inventory | `testing/suites.json` | Disjoint exact-name test selection |
| Main runner | `testing/scripts/run_checks.py` | Unit/integration selection, analysis, evidence and failure exit code |
| Database runner | `testing/scripts/run_database_tests.py` | Disposable loopback PostgreSQL setup/test/teardown |
| Optional probes | `testing/scripts/*smoke.py` and diagnostics | Explicit running-service integration checks |
| Run evidence | `testing/evidence/<UTC timestamp>/` | Raw logs, isolated cluster and JSON summary |
| Current report | `testing/RESULTS.md`, documents 06–08 | Fresh results and limitations |

The numbered `00–08` documentation filenames are unchanged. Tests and scripts
are visible in project directories. Model-test artifacts use a temporary directory
under `testing/` and are cleaned after the integration assertion. Generated run
evidence and database files are ignored by Git; source tests/runners/docs are tracked.
Historical evidence is retained as historical, without being relabeled into the
new unit/integration totals.

## System-test documentation addition

Added `testing/system/README.md` as the visible scenario/change/figure index. Source evidence remains in the local, ignored `guidelines/system-test/` directory. `testing/system/forgot-password-error-detail.png` is a report excerpt that excludes the browser callback query; the original screenshot is preserved. The Google Docs Chapter 6 report includes all 21 source screenshots (recovery as an excerpt), while the existing 00-08 filenames are unchanged. This update documents the six required changes without modifying application code.
