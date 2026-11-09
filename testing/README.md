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
