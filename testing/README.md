# SUPRA demo testing

Run commands from the repository root. Source tests remain in
[`backend/src/`](../backend/src/) and [`mobile/test/`](../mobile/test/).
This directory contains demonstration runners and visible evidence locations.

```sh
python3 testing/scripts/run_checks.py
python3 testing/scripts/smoke.py
python3 testing/scripts/schema_audit.py --backend-env
```

The first command runs backend tests, Flutter analysis and Flutter tests, continuing
through failures and returning a nonzero exit code if any check fails. It stores
logs in `testing/evidence/<UTC timestamp>/`. Rust build output stays in
`backend/target/`; Flutter uses `mobile/build/`. No `/tmp` test setup is needed.

The smoke script checks a running backend (default localhost:3000) for JSON
health 200/200, protected-route 401 and unknown-route 404. Override with
`--base-url http://your-demo-host:3000`. It does not start/stop any services.

The schema script requires `psql`. It reads `DATABASE_URL` from the shell, or
from `backend/.env` with `--backend-env`, and prints migration/schema metadata
only. It does not change schema or print credentials. Its result does not
establish that authenticated account loading succeeds.

Optional checks:

```sh
# Set SUPRA_TEST_DATABASE_URL separately to a dedicated disposable *_test DB.
python3 testing/scripts/run_checks.py --database
python3 testing/scripts/run_checks.py --builds
```

Never use the application database for the integration test. Recovery emails,
provider accounts, transit schedules, UI/device checks and demo sign-in still
need manual verification. See [test documentation](../docs/testing/00-integration.md).

Recorded execution: [RESULTS.md](RESULTS.md).

## Three testing steps

1. **Unit testing:** run `python3 testing/scripts/run_checks.py` and inspect the
   unit/widget assertions and analyzer log. Package totals also include component
   integration checks.
2. **Integration testing:** review the stand-in/client-contract results, then run
   `python3 testing/scripts/run_checks.py --database` with a dedicated test URL.
   Use the schema audit as supporting metadata evidence. The flag reruns the
   base suites; it does not create an additional set of unit results.
3. **System testing:** use `--builds` for build preparation, run
   `python3 testing/scripts/smoke.py`, then follow the manual end-to-end procedure
   in [04-test-procedure.md](../docs/testing/04-test-procedure.md).

These are the three test stages. Static analysis, metadata inspection and builds
support them; they are not additional testing stages.

## Timeout investigation and isolated database reproduction

```sh
python3 testing/scripts/account_diagnostics.py
python3 testing/scripts/database_diagnostics.py --backend-env
python3 testing/scripts/run_database_tests.py
```

The account script reads the existing Linux app session from its local preferences
and times authenticated profile, trip, inbox and preference GET requests. It
prints status/duration only, redacts user IDs, never refreshes the token itself,
and returns nonzero for failed reads. An expired session can return 401; restart
or sign in through the app rather than exporting tokens into a terminal.

Database diagnostics show aggregate waits/locks and trigger names, without
account rows or SQL text. The isolated test runner requires PostgreSQL tools
(`initdb`, `pg_ctl`, `createdb`); it provisions a new loopback-only cluster under
`testing/evidence/`, runs the ignored integration test, then stops the cluster.
It retains logs/data for demonstration and never connects to the app database.
The integration test now exercises avatar upload as well as confirmed-trip CRUD.

Live provider recency audit: `python3 testing/scripts/provider_freshness.py`.
This checks Jakarta weather/CAMS timestamps and nearby OpenAQ last-update metadata;
it reports provider failures and never prints API keys.

Authenticated three-point source/time check: `python3 testing/scripts/conditions_smoke.py`.
It reads the local desktop session without printing tokens or account data.

## Public transportation checks

```sh
# Authenticated local API: fixed public sample locations; does not save trips.
python3 testing/scripts/transit_smoke.py
# Compare Transjakarta and KRL alternatives for Monas–UI during service hours:
python3 testing/scripts/transit_smoke.py --case monas-ui
# Resource-dependent integration checks (run explicitly):
cd backend
cargo test --locked transit::gtfs::tests::supplied -- --ignored --nocapture
cargo test --locked transit::tests::live_commute -- --ignored --nocapture
cargo test --locked transit::tests::live_monas_ui -- --ignored --nocapture
```

The first Rust command needs `file_gtfs/`; the second calls the public API.
The Monas–UI test uses both and asserts that bus and KRL alternatives survive.
The authenticated smoke prints every option with its independent legs/times/fare.
The ordinary suite uses small test fixtures and local HTTP stand-ins.
See [transit setup](../backend/docs/public-transport.md) for defaults, service
horizons, attribution and geometry limitations.

## Python/PyTorch and real publisher news

Install/train/start using [ml/README.md](../ml/README.md), then:

```sh
ml/.venv/bin/python -m unittest discover -s testing/python -v
python3 testing/scripts/run_checks.py
python3 testing/scripts/run_database_tests.py
python3 testing/scripts/intelligence_smoke.py --evaluate
```

The combined runner includes Python checks when `ml/.venv` exists and explicitly
reports a missing environment. The isolated DB check verifies publisher inbox
preferences, deduplication and ownership. The system smoke uses the existing
signed-in desktop session, never prints tokens, and queues in-app news only with
`--evaluate`. Training data/runtime logs stay under `ml/data`, `ml/artifacts` and
`testing/`; source tests and scripts remain visible here.

## Selected-route assistant and news preferences

`python3 testing/scripts/assistant_smoke.py` performs read-only account preference
and severity-query checks plus one Gemini request for a public Monas–UI example.
It records the model/engine, selected route, provider status/times and response;
credentials and account IDs are never printed. Exit code 2 means the explicit
server-data fallback was used instead of Gemini. See
[the feature contract](../backend/docs/assistant-and-alerts.md).

## Alert cleanup and preference refresh

`python3 testing/scripts/alerts_smoke.py` performs read-only verification of both
inbox APIs against saved preferences and checks that Delete read requires auth.
It does not delete demo notifications or change settings. Actual dismissal,
unread preservation, owner isolation and non-regeneration are exercised only in
the disposable DB runner. Widget cases remain in
`mobile/test/news_preferences_test.dart`.

Read-state controls are now visible in the Alerts toolbar. Row checkboxes enable
**Mark selected unread**, and each item supports an individual unread toggle.
The read-only alerts smoke also verifies authentication on these mutation routes;
actual read-state writes/deletion are covered with disposable DB/client fixtures.
