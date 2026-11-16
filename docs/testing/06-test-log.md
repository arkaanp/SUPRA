# 06 — Test log

Executed **2026-11-16 at 05:30:56 UTC / 12:30:56 WIB** on
`feat/ai-integration`, base commit `e6627b5c116f7b14734bf888e85bf426b013ce30`,
with the test refactor in the working tree. The JSON summary records the local
changes; this is not a claim that the base commit alone contains the refactor.

Command from the repository root:

```sh
python3 testing/scripts/run_checks.py
```

## Recorded results

| Step | Suite | Passed | Result |
|---|---|---:|---|
| Unit | rust | 22 | PASS |
| Unit | flutter | 77 | PASS |
| Unit | python | 12 | PASS |
| Integration | rust | 24 | PASS |
| Integration | flutter | 14 | PASS |
| Integration | python | 1 | PASS |
| Integration | database | 1 | PASS |
| Integration | gtfs | 1 | PASS |

**Unit testing: 111 passed. Integration testing: 41 passed. Total: 152 passed.**
Rust inventory validation and Flutter analysis also passed, without contributing
to those totals. There were no ignored cases within the explicitly selected
suites. The two public Commute API integrations were not selected.

## Evidence

- [Machine-readable summary](../../testing/evidence/20261116T053056583997Z/summary.json)
- Unit logs: `testing/evidence/20261116T053056583997Z/unit/`
- Integration logs: `testing/evidence/20261116T053056583997Z/integration/`
- [Migrated database/API assertions](../../testing/evidence/20261116T053056583997Z/integration/database/integration.log)
- [Flutter analysis](../../testing/evidence/20261116T053056583997Z/support/analyze.log)

The database setup created and stopped a new local cluster. The supplied GTFS
check executed successfully. The default runner made no live-provider calls and
did not change demo-account data.

An earlier attempt at `20261116T053004197677Z` incorrectly reported the successful
database test as zero tests because the wrapper output omitted the nested Cargo
log. The runner was corrected and the full two-step run above passed. See
[07](07-test-incident-report.md). Previous branch/cumulative results remain
historical in Git and older dated evidence, and are not included in current totals.

## Supplied system-test record — 2026-11-16

The user supplied 21 screenshots and current notes in `guidelines/system-test/`. Unnoted features are accepted as implemented. Nine scenario groups are recorded: **5 PASS, 3 PARTIAL, 1 FAIL**. Six noted changes remain open. This reviews supplied manual evidence; it does not claim a new interactive execution or change the 152 automated-test total. Dated captures identify 12:58-13:09 WIB on 16 November; other images belong to the supplied collection without individual timestamp claims. Six SYS items await implementation/retest. See [system evidence and screenshots](../../testing/system/README.md).
