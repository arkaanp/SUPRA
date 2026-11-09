# Demo verification — 9 November 2026

Application baseline: `main` at `967a477`; documentation and scripts updated in
this merge. The pending docs-only merge was recorded in runner working-tree
metadata. No application source changed.

| Demonstration | Result |
|---|---|
| `python3 testing/scripts/run_checks.py` | Exit 0 |
| Backend suite | 30 passed; one dedicated DB test ignored |
| Flutter analyzer | No issues found |
| Flutter suite | 62 passed |
| `python3 testing/scripts/smoke.py` | All four JSON/status assertions passed: 200/200/401/404 |
| `python3 testing/scripts/schema_audit.py --backend-env` | Exit 0; five successful migration records, latest 20261109000000; expected feature columns/tables present |
| Python syntax compilation | Passed |
| Dedicated database integration | Not run |
| Release builds / authenticated UI | Not run in this cycle |

Full suite logs and JSON metadata from the visible runner are retained locally
at `testing/evidence/20261109T062032565183Z/`. They are generated artifacts rather
than committed logs. This report is the shareable evidence summary.

The account-refresh banner still requires an authenticated request trace. The
HTTP and schema results alone do not close that incident.
