# Current test results

**Automated PASS — 171 tests: 129 unit and 42 integration.**

Executed **2026-11-22 at 18:48 UTC / 2026-11-23 at 01:48 WIB**, branch
`feat/deployment`, base commit `fa79e7e6c25bd78055f73c85a98bdc94d1d0920c`,
including the Indonesian interface changes in the working tree.
Command: `python3 testing/scripts/run_checks.py`.

| Step | Suite | Passed | Result |
|---|---|---:|---|
| Unit | Rust | 22 | PASS |
| Unit | Flutter | 88 | PASS |
| Unit | Python | 19 | PASS |
| Integration | Rust | 24 | PASS |
| Integration | Flutter | 13 | PASS |
| Integration | Python | 3 | PASS |
| Integration | Database | 1 | PASS |
| Integration | GTFS | 1 | PASS |

Rust inventory and Flutter analysis also passed. Coverage includes Indonesian
labels and built-in dialogs; retained API status/enum values; localized legacy
alert display; WIB date conversion; per-source update times on Home with ML off;
weather issue time instead of future validity; and preservation of original
timestamps after a failed refresh. Forecast mode hides the current-data timestamp
section. Trip history controls wrap to accommodate longer translated labels.

Evidence: [automated summary](evidence/20261122T184850552215Z/summary.json).
The first run found outdated English assertions and a Trip history header
overflow. These were corrected before the complete passing run. This cycle does
not claim a Render redeployment or new interactive device acceptance testing.

## Historical automated run — 2026-11-22, AQI forecast fallback

**Automated PASS — 167 tests: 125 unit and 42 integration.**

Executed **2026-11-22 at 17:46 UTC / 2026-11-23 at 00:46 WIB**, branch
`feat/deployment`, base commit `5f886c8931085c9d1d9b779013f00282b3ecafe0`,
including the current working-tree changes. Command: `python3 testing/scripts/run_checks.py`.

| Step | Suite | Passed | Result |
|---|---|---:|---|
| Unit | Rust | 22 | PASS |
| Unit | Flutter | 84 | PASS |
| Unit | Python | 19 | PASS |
| Integration | Rust | 24 | PASS |
| Integration | Flutter | 13 | PASS |
| Integration | Python | 3 | PASS |
| Integration | Database | 1 | PASS |
| Integration | GTFS | 1 | PASS |

Rust inventory validation and Flutter analysis passed. This run covers current
OpenAQ NowCast fallback, the new PyTorch station-based twelve-hour AQI forecast,
Home's twelve future AQI boxes, Trip's origin forecast display, missing/stale/
flagged/duplicate station input rejection and forecast API validation. Forecast
regressions exercise application behavior, not independent forecast accuracy.
The two optional live-transit cases were not included.

Evidence: [automated summary](evidence/20261122T174639823683Z/summary.json).

A separate live Python HTTP smoke test injected Open-Meteo/CAMS failure while
using real OpenAQ and MET Norway inputs. It returned HTTP 200 with twelve future
AQI estimates, ranging from 134 to 174, and station readings through 16:00 UTC.
The result is specific to that request and time. Command:
`ml/.venv/bin/python testing/scripts/openaq_forecast_smoke.py --env-file backend/.env`.
Evidence: [live outage fallback](evidence/20261122T174648730142Z/integration/live-openaq-forecast.json).
This smoke check is separate from the 167-test total. It does not establish
accuracy against station observations or claim that Render has been redeployed.

The system-test screenshots below remain historical evidence; this cycle did
not repeat interactive device acceptance testing.

## Historical automated run — 2026-11-16

**Automated PASS — 152 tests passed: 111 unit and 41 integration.**
The 00–08 filenames are retained. System testing is documented separately from these two automated stages.

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

Optional live HTTP/provider/account probes, release builds, new interactive device executions
and model retraining were not rerun. The running demo account was not modified.
Older results remain historical in Git and dated evidence, without contributing
to this cycle's totals. Reproduction and prerequisites:
[testing/README.md](README.md).

## System-test evidence update

The user supplied 21 screenshots and current notes in `guidelines/system-test/`. Unnoted features are accepted as implemented. Nine scenario groups are recorded: **5 PASS, 3 PARTIAL, 1 FAIL**. Six noted changes remain open. This reviews supplied manual evidence; it does not claim a new interactive execution or change the 152 automated-test total. System acceptance remains incomplete pending SYS-01-SYS-06. See [screenshots, scenarios and required retests](system/README.md).
