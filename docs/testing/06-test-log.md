# Test log

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Current main verification — 2026-11-09

Application baseline: `967a477`, Linux, local configured FVM SDK and Cargo.

| ID | Testing step | Check | Result |
|---|---|---|---|
| TL-001 | 1. Unit + 2. component integration (combined suite) | `cargo test --locked --offline` | 30 passed, 0 failed, one ignored database test |
| TL-002 | 2. Integration | Dedicated database integration | NOT RUN; no dedicated test URL configured |
| TL-003 | 1. Unit (supporting analysis) | `fvm flutter analyze` | No issues found |
| TL-004 | 1. Unit + 2. component integration (combined suite) | `fvm flutter test --no-pub` | 62 passed, 0 failed |
| TL-005 | 3. System (build preparation) | Linux/web release builds | NOT RUN in this cycle |
| TL-006 | 3. System (process smoke) | `python3 testing/scripts/smoke.py` | PASS: JSON live 200, ready 200, trips 401, unknown route 404 |
| TL-007 | 2. Integration (supporting metadata) | `python3 testing/scripts/schema_audit.py --backend-env` | Trip/notification feature columns; saved_places, routine_trips, alert_decisions present |
| TL-008 | 3. System (end-to-end) | Authenticated full application demo | NOT RUN; account warning reported by user |

Initial restricted runs hit local socket and SDK-cache permissions; checks were
rerun with the required environment access before the successful results above.

## Imported branch history

The docs branch recorded 32 backend passes, 72 Flutter passes, a disposable DB
integration pass and Linux/web build successes on its own application revision.
These are historical branch results and are not evidence for main. The original
records remain accessible in `git show docs/testing:docs/testing/06-test-log.md`.

## Reproducible evidence

Run `python3 testing/scripts/run_checks.py`. Each execution retains complete
suite logs and `summary.json` under `testing/evidence/` with commit, working-tree
state and exit codes. Counts can change when tests are added; record actual output.

| New run | Revision | Case/command | Result | Evidence |
|---|---|---|---|---|
| Pending | — | Manual authenticated warning reproduction | NOT RUN | — |

## Visible runner verification

The new runner completed with exit 0: backend 30 passed/one ignored, Flutter
62 passed, analyzer clean. Local raw evidence:
`testing/evidence/20261109T062032565183Z/`.
The HTTP smoke passed all four JSON/status checks. Schema audit showed five
successful migrations through `20261109000000` and the expected feature schema.
See [shareable results](../../testing/RESULTS.md).

## Stage outcome

1. **Unit testing:** executed package suites and analysis passed.
2. **Integration testing:** component stand-ins and schema inspection passed;
   dedicated database test NOT RUN.
3. **System testing:** backend smoke passed; builds and authenticated device
   flows NOT RUN. No complete system-stage pass is claimed.
