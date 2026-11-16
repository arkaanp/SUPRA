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

## 3. System testing

The user supplied 21 screenshots and current notes in `guidelines/system-test/`. Unnoted features are accepted as implemented. Nine scenario groups are recorded: **5 PASS, 3 PARTIAL, 1 FAIL**. Six noted changes remain open. This reviews supplied manual evidence; it does not claim a new interactive execution or change the 152 automated-test total.

| ID | Scenario | Status | Outcome |
|---|---|---|---|
| ST-01 | Home: current/stale conditions, ML toggle and forecast strip | PASS | Figures 6.1-6.4; no note identifies a remaining change. |
| ST-02 | Profile and alert-preference controls | PASS | Figure 6.5; controls are accepted as implemented. |
| ST-03 | Saved places: map selection and saved list | PASS | Figures 6.6-6.8; saved Campus/Home entries are displayed. |
| ST-04 | Routine configuration, time selection and saved routine | PASS | Figures 6.9-6.13; creation and saved listing are accepted. Downstream use remains open in ST-05. |
| ST-05 | Alerts and routine consumption | PARTIAL | Figure 6.14 plus Home/routine evidence: current-trip alerts work; routine display and alert evaluation remain pending. |
| ST-06 | Assistant route/weather conversation | PARTIAL | Figure 6.15: a weather answer is displayed, but the notes report occasional irrelevant news/information. |
| ST-07 | Forgot-password email-to-reset journey | FAIL | Figure 6.16: email is sent, but its callback returns not_found instead of completing recovery. |
| ST-08 | Motorcycle/transit route display and trip UX | PARTIAL | Figures 6.17-6.19: routes and transit legs work; default metadata visibility and unavailable-data communication need changes. |
| ST-09 | Named route conditions, weather/air overlays and preview | PASS | Figures 6.20-6.21; no note identifies a remaining change. |

All 21 source images are embedded and captioned in [system evidence and screenshots](../../testing/system/README.md).
