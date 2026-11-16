# Current test results

**PASS — 152 tests passed: 111 unit and 41 integration.**
The 00–08 documentation filenames are retained with only these two testing steps.

Executed **2026-11-16 at 05:30:56 UTC / 12:30:56 WIB** on
`feat/ai-integration`, base commit `e6627b5c116f7b14734bf888e85bf426b013ce30`,
with the test refactor in the working tree. The JSON summary records the local
changes; this is not a claim that the base commit alone contains the refactor.

```sh
python3 testing/scripts/run_checks.py
```

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

Flutter analysis and Rust inventory validation passed. Each case is counted once;
Python includes four new classification guards. Existing 91 Flutter and 9 ML/news
cases remain across the two steps. Rust executes 48 of its 50 cases, including
the isolated database and supplied-feed checks; the other two public API cases
are opt-in and were not run.

Raw local evidence:
[`testing/evidence/20261116T053056583997Z/summary.json`](evidence/20261116T053056583997Z/summary.json).
The summary records exact commands, log paths, counts, exit codes, commit and
working-tree state. PostgreSQL data/server/API logs remain in the integration
evidence directory; the isolated cluster was stopped after the check.

The first refactored run miscounted the passing nested database result. That
reporting issue was fixed and both steps rerun successfully. See
[incidents](../docs/testing/07-test-incident-report.md) and the
[full test log](../docs/testing/06-test-log.md).

Optional live HTTP/provider/account probes, release builds, device walkthroughs
and model retraining were not rerun. The running demo account was not modified.
Older results remain historical in Git and dated evidence, without contributing
to this cycle's totals. Reproduction and prerequisites:
[testing/README.md](README.md).
