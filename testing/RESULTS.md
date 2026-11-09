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

## Three-stage interpretation

1. **Unit testing:** recorded package checks and analysis passed; aggregate suite
   counts include component integration assertions.
2. **Integration testing:** component checks and schema audit passed; dedicated
   database integration was not run.
3. **System testing:** HTTP smoke passed; release builds and full authenticated
   UI/device checks were not run in this cycle.

## Timeout-fix verification — 2026-11-09

Changes after the recorded `3fbc286` baseline:

1. **Unit testing:** backend 33 passed/one DB case ignored; Flutter 66 passed;
   analysis clean. Added stalled refresh/header/body tests, late-auth write
   prevention, upload/trip timeout mapping, JWKS failure handling and immediate
   alert-queue acknowledgement.
2. **Integration testing:** dedicated local database suite passed, including
   authenticated avatar PNG upload and confirmed-trip persistence. Evidence:
   `testing/evidence/db-20261109T072105086787Z/integration.log`.
3. **System testing:** rebuilt backend and Flutter hot restart completed. The
   desktop session refreshed; authenticated profile/trip reads returned 200 in
   approximately 0.4 seconds. HTTP smoke passed 200/200/401/404. User-visible
   upload/trip retry confirmation is still pending; no complete system pass yet.

Combined-suite evidence: `testing/evidence/20261109T072211984744Z/`.
Auth calls now have a 5-second transport deadline and a 6-second token wait.
JWKS verification has a 4-second overall budget (3-second upstream HTTP);
DB pool acquisition is 4 seconds, statements 6 seconds and locks 3 seconds.
Inbox reads no longer run provider evaluation; manual evaluation acknowledges
asynchronously. Account errors retain their cause and save timeouts advise
checking persisted state before retrying.
