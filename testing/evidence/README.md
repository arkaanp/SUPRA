# Local execution evidence

`python3 testing/scripts/run_checks.py` creates a dated directory with:

- `unit/`: Rust, Flutter and Python logs.
- `integration/`: Rust, Flutter, Python, GTFS and database logs; optional live transit log.
- `integration/database/`: isolated PostgreSQL data, server log and raw API-test log.
- `support/`: Rust discovery and Flutter analyzer logs, excluded from test totals.
- `summary.json`: stage selection, exact Rust partition, commit, working-tree changes,
  per-check counts, commands, log paths, exit codes and final status.

Standalone database runs create `db-<UTC timestamp>/` directories. Generated
evidence is ignored by Git; source scripts and the checked-in
[test log](../../docs/testing/06-test-log.md) make the procedure reviewable.
Older runs retain their original layout and are historical evidence. Review
logs before sharing them outside the project.
