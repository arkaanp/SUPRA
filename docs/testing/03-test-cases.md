# 03 — Test cases

The table is a coverage index. Executable assertions are authoritative; the Rust
inventory is [`testing/suites.json`](../../testing/suites.json), while Flutter
and Python discover all tests under their corresponding stage directory.

## 1. Unit testing

| ID | Coverage | Main sources | Expected behavior |
|---|---|---|---|
| UT-01 | Validation and errors | Rust `validation`, `error`, avatar and notification validation cases | Invalid requests are rejected, errors sanitized, unread selections bounded, images normalized |
| UT-02 | Conditions and hazards | Rust alerts/conditions/intelligence cases; Flutter current_conditions, environmental_zone, route_environment_samples | Correct freshness/category handling; stale or forecast evidence does not become a current hazard |
| UT-03 | Routing, maps and transit display | Flutter route_planner, map_location_selection, geographic_tile_map, transit_journey, commute_recommendations | Coordinates, overlays, named samples and route option presentation stay consistent |
| UT-04 | Inbox and preferences | Flutter news_preferences | Severity changes immediately hide ineligible existing news; failed saves roll back; visible read/delete controls and selected unread work |
| UT-05 | Assistant and account views | Flutter ai_assistant, home_screen, login_input; Rust agent validation | Selected route/evidence is bounded; unavailable values remain explicit; view state handles success/failure |
| UT-06 | News and ML logic | Python unit/test_intelligence.py; Flutter ml_forecast | Dates, trust, severity, chronological splits, input gaps, scope and hourly cache boundaries enforced |
| UT-07 | Suite completeness | Python unit/test_suite_partition.py | Missing, duplicate, removed or empty Rust classifications fail |

Other unit files retain model decoding, conditions caching, trip history, wind
arrow and application widget regressions.

## 2. Integration testing

| ID | Coverage | Main sources | Expected behavior |
|---|---|---|---|
| IT-01 | JWT/JWKS and protected router | Rust auth/routes/health integration cases | Verified subject injected, spoofed paths rejected, correct health/method/404 responses |
| IT-02 | Conditions, mobility, Gemini and intelligence adapters | Rust conditions/mobility/agent integration cases | HTTP contracts preserved, source data normalized, failures explicit, server evidence sent to assistant |
| IT-03 | Mobile HTTP/auth contracts | Flutter integration/ | Headers, payloads, timeouts, errors, SDK sessions, provider geometry and geocoding handled correctly |
| IT-04 | GTFS and transit API planning | Rust transit integration cases plus supplied-feed case | Calendar/transfer/pickup rules honored; matching vehicles retained; valid local bus route survives API outage |
| IT-05 | PyTorch artifact | Python integration/test_forecast_artifact.py | Checkpoint reload produces twelve finite hours; traffic unavailable; insufficient history rejected |
| IT-06 | PostgreSQL migrations and ownership | Rust db_tests, isolated database runner | Per-user CRUD, trip/avatar persistence, preferences, alert thresholds, selected unread, read deletion and non-regeneration verified |
| IT-07 | Optional public transit integrations | Rust `live` group, `--live` | Gondangdia–Depok route and Monas–UI bus/KRL alternatives verified against public schedules |

IT-07 is not part of the default offline-capable run. Optional running-service
integration scripts are documented in [testing/README.md](../../testing/README.md)
and have no passing status unless executed and recorded in the current cycle.
