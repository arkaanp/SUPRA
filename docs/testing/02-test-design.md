# 02 — Test design

## 1. Unit testing

Unit tests exercise a bounded function, model, repository/cache or widget using
injected dependencies. Flutter widget tests inspect rendering and local state
without connecting to the backend. Python unit tests cover news parsing,
chronological split boundaries, invalid/stale inputs and hourly cache behavior.
Rust unit tests cover validation, hazards, freshness selection, payload bounds,
image decoding, geometry parsing and error mapping.

Sources: `mobile/test/unit/`, `testing/python/unit/`, and the `unit` list in
[`testing/suites.json`](../../testing/suites.json). Rust assertions stay beside
production modules so they can access private logic.

## 2. Integration testing

Integration tests connect components across explicit boundaries:

| Boundary | Design |
|---|---|
| Router, authentication and providers | Axum middleware/handlers plus local HTTP/JWKS/provider responses; HTTP errors, timeouts and response normalization |
| Flutter clients and auth | HTTP adapters, authenticated headers, status mapping, SDK contracts and loopback geocoding/routing servers |
| Transit ingestion and planning | CSV/calendar/frequency/transfer fixtures and the supplied Transjakarta feed; API vehicle matching and outage fallback |
| Model artifacts and inference | Save/load a PyTorch checkpoint, inject hourly history, verify twelve finite forecast hours and missing traffic |
| API, migrations and database | New loopback PostgreSQL cluster, migrated schema, authenticated handlers, ownership and persistence assertions |

Sources: `mobile/test/integration/`, `testing/python/integration/`, and Rust
manifest groups `integration`, `database`, `gtfs`, `live`. The two `live` tests
call the public Commute API only when `--live` is selected.

## Separation and evidence

Mixed Flutter and Python files have been split at test boundaries. Rust uses
exact full test names; discovery rejects duplicates, removed entries, empty
groups and new unclassified tests. Four unit regressions guard this partition.
Normal Cargo/Flutter totals are not reused as unit-only totals.

The runner rejects empty test results, records each check's exit code and count,
and retains separate unit/integration logs. Analysis and inventory are supporting
checks. Controlled integration responses establish adapter behavior; current
external-provider availability requires an explicitly executed live integration.
