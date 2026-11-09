# Test documentation — integration overview

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

SUPRA is a Flutter client backed by Rust/Axum, Supabase Auth and PostgreSQL.
Routing, environmental providers and Gemini are external integrations.
This cycle targets the current demo, not production acceptance.

## Documents

| Document | Purpose |
|---|---|
| [Plan](01-test-plan.md) | Scope and acceptance |
| [Design](02-test-design.md) | Boundaries and techniques |
| [Cases](03-test-cases.md) | Executable and manual catalog |
| [Procedure](04-test-procedure.md) | Reproducible commands |
| [Transmittal](05-test-item-transmittal-report.md) | Delivered items |
| [Log](06-test-log.md) | Recorded evidence |
| [Incidents](07-test-incident-report.md) | Account warning and follow-up |
| [Summary](08-test-summary-report.md) | Current outcome |

## Current evidence

- Backend: 30 passed, one database test ignored.
- Flutter: 62 passed; analyzer clean.
- Running local backend readiness: HTTP 200.
- Read-only target schema inspection: newer trip/notification columns and saved
  places, routines and alert-decision tables present.
- Authenticated application flows, release builds and dedicated DB integration:
  not rerun in this cycle.

[Demonstration scripts](../../testing/README.md) retain logs under
`testing/evidence/`. Source suites remain next to the application packages.

PASS means executed successfully; PARTIAL means only a narrower boundary was
checked; NOT RUN means no current evidence. Earlier `docs/testing` counts of
32 backend passes and 72 Flutter passes belong to its application revision,
not to this main baseline.
