# 07 — Test incident report

## Current cycle — 2026-11-16

| Incident | Step | Observation | Resolution | Status |
|---|---|---|---|---|
| TEST-001 | Integration testing | The first refactored runner reported zero database tests and a failed aggregate, although the nested PostgreSQL/Cargo log showed one passing test | Count assertions from `integration/database/integration.log`, retain the wrapper exit code, and rerun both steps | Resolved; final run passed |

First attempt: `testing/evidence/20261116T053004197677Z/`.
Verified rerun: `testing/evidence/20261116T053056583997Z/`.
The runner continues to fail a check if no passing assertions are found, or if
an exact Rust selection executes a different count from its manifest.

No application assertion failures remained in the final unit or integration
run. Optional live provider/service probes were not rerun; their availability is
not established by these local results. Earlier account-refresh or device
observations have not been retested or declared resolved in this test-only cycle.

## Reporting rules

Record new incidents against unit testing or integration testing, include the
command/log and actual versus expected behavior, then retain rerun evidence.
Missing SDKs, ML dependencies, database tools or feed files fail their required
checks; they must not be silently converted into passing or skipped coverage.
