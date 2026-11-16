# Test documentation — unit and integration testing

SUPRA is a Flutter app with Rust/Axum, PostgreSQL, Supabase Auth, transit and
environmental adapters, a Gemini assistant, and a Python/PyTorch service.
This documentation covers the current demo on `feat/ai-integration`.

The existing **00–08 filenames and document structure are retained**. There are
exactly two testing steps:

| Step | Purpose | Executable sources |
|---|---|---|
| 1. Unit testing | Validate isolated logic, models and widgets with injected dependencies | Rust cases classified as `unit`, `mobile/test/unit/`, `testing/python/unit/` |
| 2. Integration testing | Validate HTTP/client contracts, middleware, providers, GTFS ingestion, model persistence, migrations and database ownership | Rust integration groups, `mobile/test/integration/`, `testing/python/integration/` |

Static analysis and test-inventory validation support these two steps.
They do not contribute to test totals. Each test is counted in one step only.

| Document | Purpose |
|---|---|
| [01 — Plan](01-test-plan.md) | Scope, prerequisites and acceptance |
| [02 — Design](02-test-design.md) | Test boundaries and classification |
| [03 — Cases](03-test-cases.md) | Executable coverage catalog |
| [04 — Procedure](04-test-procedure.md) | Reproducible commands |
| [05 — Transmittal](05-test-item-transmittal-report.md) | Revision and delivered test assets |
| [06 — Log](06-test-log.md) | Fresh execution evidence |
| [07 — Incidents](07-test-incident-report.md) | Issues found during this cycle |
| [08 — Summary](08-test-summary-report.md) | Results and verification boundaries |

Run `python3 testing/scripts/run_checks.py` from the repository root. The runner
executes both steps, provisions its own PostgreSQL cluster, and retains raw logs
under `testing/evidence/`. See [testing/README.md](../../testing/README.md) for
individual steps and optional live integrations. Current results are in
[testing/RESULTS.md](../../testing/RESULTS.md); older dated evidence remains historical.
