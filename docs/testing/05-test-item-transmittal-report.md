# Test item transmittal report

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Delivered

- Nine testing documents imported from `docs/testing` and aligned with main.
- `testing/README.md` and Python scripts for suites, HTTP smoke and schema audit.
- Local evidence directory with per-run logs and JSON summaries.
- Existing Rust and Dart test source retained in its original package locations.

## Not included in this merge

The source branch also has application/UI changes and additional regression
files. Those are excluded: display-preference persistence, shared Trip ML toggle,
16:9 test files and expanded chat-context tests are not claimed as delivered.

## Dependencies

Cargo/Rust, FVM Flutter/Dart, Python 3; running backend for smoke; psql plus
configured database access for metadata inspection. Integration needs
`SUPRA_TEST_DATABASE_URL` targeting a disposable *_test database.

Runtime keys are server-side. Client defines are public build configuration;
set an explicit API address for the demo device. OTP and incident-feed services
need separate setup. Push notifications and trained ML inference are not delivered.

## Handoff by testing step

| Step | Delivered items | Remaining execution |
|---|---|---|
| 1. Unit testing | Rust/Dart source suites, analysis and package runner logs | Rerun after changes |
| 2. Integration testing | Stand-in contracts, ignored DB test, schema-audit script | Dedicated database run |
| 3. System testing | HTTP smoke script, build commands, manual demo procedure | Device and authenticated end-to-end run |

## Acceptance

Local automated suites passed at the recorded baseline. Account refresh remains
under investigation. Live application flows, release builds and dedicated
integration need current execution evidence before they are marked passed.
