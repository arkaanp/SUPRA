# 04 — Test procedure

Run from the repository root with the prerequisites in [01](01-test-plan.md).

## 1. Unit testing

```sh
python3 testing/scripts/run_checks.py --stage unit
```

This validates classification, runs only the unit Rust/Flutter/Python cases,
and runs static analysis. Review `unit/*.log`, `support/analyze.log` and
`summary.json` in the printed evidence directory. Any failure must be resolved
before accepting this step.

## 2. Integration testing

```sh
python3 testing/scripts/run_checks.py --stage integration
```

This executes local HTTP/client/provider/GTFS tests, Flutter integration clients,
Python checkpoint inference, a fresh PostgreSQL cluster and the supplied feed.
The cluster's migrations and API assertions run under `integration/database/`;
it is stopped after testing. Data/logs remain in that evidence directory for review.
No application database URL is needed or used by the runner.

For one combined execution, in step order:

```sh
python3 testing/scripts/run_checks.py
```

Optional public schedule checks remain part of integration testing:

```sh
python3 testing/scripts/run_checks.py --stage integration --live
```

They require outbound network and the local feed, and depend on provider/service
time availability. They are recorded separately from the default checks.

## Review and record

Inspect commands, commit, working-tree state, per-check counts and exit codes in
`summary.json`. Supporting inventory/analyzer checks do not add to totals. Keep
unit and integration results separate in [06](06-test-log.md) and
[08](08-test-summary-report.md). A changed test suite must have fresh evidence;
previous branch results do not establish a pass for the current code.

Optional signed-in service probes are listed in
[testing/README.md](../../testing/README.md); they are not prerequisites for the
local two-step run. Do not use account-mutating probe flags on the demo account
as part of this procedure.
