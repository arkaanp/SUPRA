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

Record new incidents against unit, integration or system testing, include the
command/log and actual versus expected behavior, then retain rerun evidence.
Missing SDKs, ML dependencies, database tools or feed files fail their required
checks; they must not be silently converted into passing or skipped coverage.

## Open system-test changes

| ID | Area | Recorded issue | Required change / retest |
|---|---|---|---|
| SYS-01 | Password recovery | Email is sent but the recovery callback returns not_found. | Complete the callback/reset-screen handoff. Retest from the recovery email through password update and sign-in. |
| SYS-02 | Assistant relevance | The assistant sometimes includes unrelated news or information. | Prioritize the question and current route/time; suppress unrelated reports. Retest rain/air/route questions with relevant and unrelated news available. |
| SYS-03 | Routine visibility | Saved routines are not displayed on Home or Alerts. | Surface enabled saved routines on both pages and refresh them after creation, edits and deletion. Verify days, departure time and endpoints. |
| SYS-04 | Routine alerts | Only the current trip is evaluated; routine evaluation is not yet included. | Evaluate enabled routines at their scheduled pre-departure window using routine/profile preferences. Retest due, disabled, non-due and opted-out routines. |
| SYS-05 | Trip metadata | OpenAQ metadata and provider details are exposed by default. | Collapse technical details by default behind an information control. Keep essential values and freshness visible and make source details available on demand. |
| SYS-06 | Transit unavailability | Public-transport data unavailability is not communicated clearly enough. | Show a clear unavailable-data state and actionable retry/alternative guidance. Distinguish unavailable service data from a returned itinerary with a missing fare. |

All six items are OPEN; no fix is claimed. The older general backlog is not treated as fresh failures where the screenshots and current notes show an implemented feature. See [system evidence and screenshots](../../testing/system/README.md).
