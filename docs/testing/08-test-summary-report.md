# 08 — Test summary report

The test refactor and fresh run are complete. The existing **00–08** filenames
are preserved, with **unit testing** and **integration testing** as the two steps.

Executed **2026-11-16 at 05:30:56 UTC / 12:30:56 WIB** on
`feat/ai-integration`, base commit `e6627b5c116f7b14734bf888e85bf426b013ce30`,
with the test refactor in the working tree. The JSON summary records the local
changes; this is not a claim that the base commit alone contains the refactor.

## 1. Unit testing

**111 passed:** Rust 22, Flutter 77, Python 12. Existing isolated regressions
remain, with four additional guards against missing/overlapping Rust test
classification. Alert widget cases cover preference refresh, selected unread,
visible controls and read deletion state handling.

## 2. Integration testing

**41 passed:** Rust component/API cases 24, Flutter client cases 14,
Python checkpoint/inference 1, migrated PostgreSQL/API case 1, and supplied
Transjakarta GTFS case 1. The database case verifies multiple authenticated
persistence/ownership operations, including read-state and deletion behavior;
it counts as one executable test, not one test per assertion.

**Overall: 152 passed, zero failed.** Flutter analysis and inventory validation
also passed. See [06 — Test log](06-test-log.md) for raw evidence and the exact
command. The first runner reporting issue was corrected before this final pass.

## Boundaries

The test suite now lives in explicit unit/integration source directories for
Dart and Python; Rust uses a complete, disjoint exact-name inventory. Tests and
scripts remain visible in the repository, and generated evidence stays under
`testing/evidence/`.

Two public Commute API tests remain opt-in and were not rerun. Signed-in
running-service probes, release builds, device walkthroughs, current provider
availability and model retraining were outside this cycle. These results verify
the executable contracts listed above, rather than a new live-service/model
quality claim. Historical evidence is not added to current totals.
