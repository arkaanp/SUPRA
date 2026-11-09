# 02 — Test Design

| Field | Value |
|---|---|
| Test design ID | `TD-2026-11-09-01` |
| Test cycle | `TC-2026-11-09-01` |
| Branch / commit | `feat/migration-from-prototype` @ `5a5e45d` |
| Date | 2026-11-09 |
| Related documents | [`01-test-plan.md`](01-test-plan.md), [`03-test-cases.md`](03-test-cases.md) |

## 1. Design objectives

The design derives test conditions from four sources:

1. The feature contract in `backend/docs/commute-features.md` and
   `backend/docs/current-conditions.md`.
2. The bug and feature list in `guidelines/bugs-and-to-do.md`.
3. The database migration `20261109000000_commute_features.sql`.
4. The user-facing requirement that forecasts show temperature, AQI, and weather
   separately, with no fabricated ML values.
5. Tester feedback from the current review: visible rain/AQI/traffic/temperature
   indicators, stale-first outage behavior, optional ML display, 16:9 layout,
   Gemini condition reading, chat scope control, and verified-news relevance for
   saved places.

The design prioritizes the failures that produce misleading transportation or
environmental advice: stale data presented as live, fabricated routes or
incidents, cross-user data access, duplicate alerts, and falsely confident
recommendations.

## 2. Design techniques

| Technique | Applied to |
|---|---|
| Equivalence partitioning | Coordinates inside/outside Greater Jakarta; valid/invalid modes; fresh/stale signals; verified/unverified incidents |
| Boundary value analysis | Latitude/longitude limits; PM2.5 35.5; rain 0.2 and 1.0 mm; traffic confidence 0.5; weekday 0–6; departure minute 0–1439; lead minutes 5–180; waypoint count 1/1000; polyline limits |
| State transition | Signed out → signed in → recovery → password updated; trip planned → confirmed → active → finished; alert target unchecked → claimed → evaluated |
| Decision tables | Environmental hazard combinations; recommendation penalties by mode and freshness; incident relevance by endpoint vs route geometry |
| Negative testing | Missing/invalid token; wrong user path; malformed JSON; unknown fields; provider 401/403/429/timeout/malformed/oversized; expired recovery code |
| Contract testing | Axum response shapes; mobile `fromJson`/`toJson`; Valhalla and OTP response parsing; notification source/context |
| Idempotency testing | Running SQLx migrations twice; repeated alert evaluation; notification `(user_id, event_key)` uniqueness |
| Error guessing | Unapplied migration; schema drift; stale process vs current binary; Flutter nullable-switch compile failure; stale preferences fixtures |
| Layout/viewport testing | Render each top-level screen at 360×640 logical (16:9) and assert no `RenderFlex` overflow; exercise the Home location picker at the same size |
| Context-boundary testing | Condition snapshots are labelled with status/source/time/stale and treated as untrusted data; out-of-scope chat is refused before provider invocation |

## 3. Architecture and interfaces under test

| Interface | Producer | Consumer | Contract |
|---|---|---|---|
| `/api/users` | Axum | Flutter | Profile upsert/list; verified subject only |
| `/api/trips` | Axum | Flutter | Planned/confirmed trip; mode; active window; route geometry |
| `/api/places` | Axum | Flutter | Saved place CRUD with ownership |
| `/api/routines` | Axum | Flutter | Routine CRUD with owned places and schedule |
| `/api/mobility/plan` | Axum | Flutter | Mode-specific provider geometry, duration, distance, steps, provenance |
| `/api/conditions/current` | Axum | Flutter | Three independent signals with status and timestamps |
| `/api/alerts/evaluate` | Axum | Flutter | HTTP 202 queued evaluation; saved-place news and trip alerts |
| `/api/users/{id}/notifications` | Axum | Flutter | Inbox with source URL, context, expiry, per-user incident deduplication |
| `/api/users/{id}/preferences` | Axum | Flutter | Alert flags including relevant news |
| `/api/trips/{id}/finish` | Axum | Flutter | End current-trip alert eligibility without deleting history |
| `/api/agent/chat` | Axum → Gemini | Flutter | Backend-only model call; bounded condition context; deterministic scope refusal; 503 on missing/failed provider |

## 4. Unit test design

### 4.1 Backend

| Area | Conditions | Cases |
|---|---|---|
| Auth | Missing, malformed, expired, wrong issuer/audience/role token; path ID spoofing | `UB-001`, `UB-002` |
| Validation | Required strings; confirmed-trip coordinate completeness; waypoint shape/count; mode enum; coordinate envelope | `UB-003`, `UB-004`, `UB-006` |
| Error mapping | Row not found → 404; constraint violation → 400/409; internal error → sanitized 500 | `UB-005` |
| Conditions | Provider success; missing credentials; 401/403/429; malformed/oversized; timeout; weather fallback without discarding healthy signals | `UB-007`–`UB-009` |
| Alerts | WIB weekday and midnight boundaries; stale and forecast signals; PM2.5/rain/traffic thresholds; traffic confidence; incident validation/relevance; saved-place 3 km relevance and per-user dedup keys | `UB-010`–`UB-013`, `IN-017` |
| Mobility | Polyline decode success/failure; OTP non-transit rejection; Valhalla/OTP real HTTP stand-in | `UB-014`, `UB-015` |
| Avatar | Filename-only, signature-only, non-image rejection; decode/resize/re-encode PNG | `UB-016` |
| Agent | Credential-like input rejection; invalid history rejection; provider failure produces 503, not a simulated answer; bounded condition context; deterministic scope guard | `UB-017`, `UB-021`, `UB-022` |
| Router | Public health; JSON 404; method 405; auth before method errors | `UB-018`–`UB-020` |

### 4.2 Mobile

| Area | Conditions | Cases |
|---|---|---|
| Login focus | Repeated failed sign-in and visibility toggles keep the password field editable | `UM-001` |
| Recovery | Request email, verify code, update password, clear recovery state, reject mismatched/short password | `UM-002`, `UM-015` |
| Serialization | Notification preference news flag; notification source/expiry; trip mode defaults; place/routine JSON | `UM-003`–`UM-006` |
| Routing model | Mode API values and labels; provider geometry validation; wrong mode rejection | `UM-007`, `UM-013` |
| Recommendations | Fresh PM2.5/rain penalties; stale/missing values do not trigger current-risk advice; duration preference; packing items; traffic is explanatory only | `UM-008`, `UM-009` |
| Forecast | Separate temperature, AQI, and weather fields; pending ML status | `UM-010` |
| Stale data | Original timestamp retained; STALE labels; no advancement on partial failure | `UM-011` |
| Indicators | Rain, temperature, AQI, and traffic remain visible with `No data` or `STALE` rather than disappearing | `UM-017` |
| ML display | Off by default; explicit toggle; persisted preference; `ML unavailable` when no model value | `UM-018`, `UM-019` |
| Layout | Home, Assistant, Alerts, and Trip render at 360×640 without overflow | `UM-020` |
| Map/geocoding | Raster tiles render; explicit selection; invalid/no-match/outage behavior | `UM-012`, `UM-014` |
| Assistant | No API-key prompt; no fabricated context; labelled conditions/STALE sent to backend | `UM-016`, `UM-021` |

## 5. Integration test design

### 5.1 Database and handler integration

The dedicated integration test applies the SQLx migrator twice, then exercises
the router with two locally signed identities.

| Condition | Assertion | Case |
|---|---|---|
| Fresh schema | All migrations apply | `IN-001` |
| Idempotency | Second migrator run succeeds | `IN-001` |
| Profile isolation | User A cannot read User B; list returns only self | `IN-003` |
| Trip ownership | Cross-user read/update/delete/route creation denied | `IN-004` |
| Trip confirmation | Confirmed trip stores confirmed timestamp and coordinates | `IN-005` |
| Trip finish | Cross-user finish denied; owner finish returns finished | `IN-005` |
| Preferences | Defaults preserved; partial update preserves other flags | `IN-006` |
| Notifications | Cross-user read/update denied; list scoped | `IN-007` |
| Places | Create/read/update; cross-user list empty; cross-user update/delete denied | `IN-008` |
| Routines | Create/list; cross-user list empty; cross-user update/delete/create denied | `IN-009` |
| Alert endpoint | Manual check returns 202 `{queued:true}` | `IN-010` |
| Saved-place news | Verified, unexpired incident within 3 km creates one notification per user/incident; outside/expired ignored | `IN-017` |
| Account deletion | Owned trips are removed | `IN-005` |

### 5.2 Provider and client integration

| Condition | Assertion | Case |
|---|---|---|
| Conditions HTTP | Authenticated lookup normalizes three providers | `IN-011` |
| Conditions failure | Rate limit, malformed body, timeout sanitized; healthy signals retained | `IN-011` |
| Valhalla stand-in | Walking/motorcycle geometry and duration parsed | `IN-012` |
| OTP stand-in | Transit itinerary parsed; non-transit rejected | `IN-012` |
| Agent provider | Missing/failed Gemini returns 503; no fabricated reply | `IN-013` |
| Avatar | Valid image decoded, resized, re-encoded; invalid rejected | `IN-014` |
| Mobile client | Bearer header, origin restriction, API error mapping | `IN-015` |
| Router | 401 before method handling; unknown route JSON 404 | `IN-016` |

## 6. System test design

### 6.1 Application flows

| Flow | Steps | Expected | Case |
|---|---|---|---|
| App startup | Start web/Linux app with approved config | Login or shell renders; no missing-config crash | `SY-001` |
| Sign-in/out | Valid sign-in, sign-out, expired session | Shell appears; session clears safely | `SY-002` |
| Recovery | Request email, enter code/link, set password | Recovery screen; password updated; normal sign-in works | `SY-003` |
| Home forecast | Load home with live and stale conditions; toggle ML display | Temp, AQI, weather visible separately; indicators remain; STALE labels retain timestamps; ML output unavailable rather than invented | `SY-004` |
| Trip planning | Choose car/walk/motorcycle/transit; select a history item; confirm; toggle ML | Provider geometry or explicit unavailable message; no synthetic route; ML chip says unavailable when no prediction | `SY-005` |
| Places/routines | Create/edit/delete place; create routine; plan now | Ownership-safe CRUD; schedule and mode persist | `SY-006` |
| Alerts | Queue manual check; open inbox; end current-trip alerts | Queued status, inbox items, source links, saved-place news, finish works | `SY-007` |
| Profile/avatar | Update name; upload valid/invalid avatar | Valid avatar served; invalid rejected | `SY-008` |
| Offline/provider outage | Disable network/provider | Last-known stale data shown; no fabricated values | `SY-009` |
| Linux map | Open trip map | Raster basemap renders and selection works | `SY-010` |
| Builds | Linux and web release | Both builds succeed | `SY-011` |
| Chat scope | Ask a commute question, then an unrelated request | Relevant answer; out-of-scope request refused; no fabricated readings | `SY-014` |
| Phone layout | Open Home, Assistant, Alerts, and Trip at 16:9 | No overlapping or clipped controls | `SY-013` |

## 7. Test data design

| Data class | Values |
|---|---|
| Service envelope | Latitude −6.9 to −5.8; longitude 106.3 to 107.3 |
| Out-of-envelope | Latitude −7.1 or −5.5; longitude 106.0 or 107.6 |
| PM2.5 | 12.0 (low), 35.4 (below), 35.5 (threshold), 80.0 (high) |
| Rain | 0.0, 0.2, 1.0, 20.0 mm |
| Traffic | free-flow 40 km/h, speed 25 km/h (normal), speed 15 km/h (disrupted), confidence 0.4/0.5/0.9 |
| Weekdays | Monday=0 … Sunday=6; Sunday 23:50 WIB; Monday 00:10 WIB |
| Routine | departure 420 (07:00), lead 30; 0 and 1439 valid; 1440 invalid |
| Places | home/work/school/custom; owned and cross-user IDs |
| Trips | unconfirmed (no coordinates), confirmed (four coordinates), active, finished |
| Route geometry | ≥2 valid points; one-point, non-finite, >1000 points, broken polyline |
| Incidents | verified/unverified, future/expired, HTTPS/non-HTTPS, inside/outside 1.5 km corridor, saved place inside/outside 3 km |
| Condition context | available/stale/unavailable signals; AQI 0/88/500/501; bounded status/source/time strings |
| Viewport | 360×640 logical (16:9 phone reference); 390×844 normal widget reference |
| Auth | valid token, missing token, malformed token, wrong subject, expired token |

## 8. Environment design

| Environment | Database | Auth | Providers |
|---|---|---|---|
| Unit | None | Local claims/parser fixtures | Mock HTTP |
| Integration | Disposable PostgreSQL `*_test` | Local JWT fixture + mock JWKS | Local HTTP stand-ins |
| Backend smoke | Disposable PostgreSQL | Not exercised beyond 401 gate | Not called |
| Live system | Approved staging/application database | Approved Supabase project | Approved live/stand-in configuration |

The live system environment is not reproduced in this repository because it
requires private configuration. Its checks are documented as manual procedures.

## 9. Automation design

| Layer | Command / location |
|---|---|
| Backend unit | `cargo test --locked --target-dir <temp-target>` |
| Backend integration | `SUPRA_TEST_DATABASE_URL=<disposable-test-url> cargo test --locked -- --ignored` |
| Flutter analyzer | `fvm flutter analyze` |
| Flutter tests | `fvm flutter test` |
| Flutter layout regression | `fvm flutter test test/layout_16_9_test.dart` |
| Flutter feedback regressions | `fvm flutter test test/display_preferences_test.dart test/trip_display_preferences_test.dart test/home_screen_test.dart test/ai_assistant_test.dart` |
| Linux build | `fvm flutter build linux` |
| Web build | `fvm flutter build web` |
| Backend smoke | Start compiled binary with isolated env; `curl` health/auth/fallback |
| System UI | Manual with approved account/configuration |

Automated tests must not read `.env` or `config/local.json` to construct
assertions. Integration tests receive only the disposable test database URL.

## 10. Traceability

| Requirement | Design conditions | Cases |
|---|---|---|
| `REQ-FORECAST` | Three independent fields; pending state | `UM-010`, `SY-004` |
| `REQ-INDICATORS` | Always-visible indicators; `No data`; `STALE`; retained timestamps | `UM-011`, `UM-017`, `SY-004`, `SY-009` |
| `REQ-MLTOGGLE` | Off by default; persisted opt-in; unavailable when absent | `UM-018`, `UM-019`, `SY-004`, `SY-005` |
| `REQ-LAYOUT` | 16:9 viewport; no overflow on four top-level screens | `UM-020`, `SY-013` |
| `REQ-STALE` | Freshness windows; timestamp retention; partial failure | `UB-007`, `UM-011`, `SY-004`, `SY-009` |
| `REQ-RECOVERY` | Email → code → password state machine | `UM-002`, `UM-015`, `SY-003` |
| `REQ-MODES` | Mode enum; provider geometry; OTP transit | `UB-014`, `UB-015`, `IN-012`, `SY-005` |
| `REQ-RECOMMEND` | Decision table over duration/PM/rain/freshness | `UM-008`, `UM-009`, `SY-005` |
| `REQ-PLACES` | Ownership; foreign keys; schedule bounds | `IN-008`, `IN-009`, `SY-006` |
| `REQ-ALERTS` | Due window; freshness; dedup; feed validation; saved-place relevance | `UB-010`–`UB-013`, `IN-010`, `IN-017`, `SY-007` |
| `REQ-HISTORY` | Confirmed events only; mode; finish | `IN-004`, `IN-005`, `SY-005` |
| `REQ-GEMINI` | Backend-only; 503 on failure | `UB-017`, `IN-013` |
| `REQ-CHAT-CONTEXT` | Bounded labelled context; stale flag; untrusted data | `UB-022`, `UM-021` |
| `REQ-CHAT-SCOPE` | Deterministic refusal before model call | `UB-021`, `UM-016`, `SY-014` |
| `REQ-AVATAR` | Content/size/dimension validation; re-encode | `UB-016`, `IN-014`, `SY-008` |
| `REQ-MIGRATION` | Fresh + idempotent migration | `IN-001`, `IN-002` |
| `REQ-REGRESSION` | Original bug reproductions | `UM-001`, `UM-012`, `UM-013`, `UM-014` |

## 11. Coverage rationale and gaps

The highest-risk behaviors have deterministic coverage: auth ownership,
migration validity, provider parsing, stale/forecast exclusion, alert timing,
and the three-field forecast. The following are intentionally not claimed as
covered:

- Live GTFS schedule correctness and real-time arrivals.
- Live verified-news coverage and source reliability; saved-place relevance is
  implemented but not exercised against a reviewed live feed.
- ML prediction values or accuracy; the toggle is verified only to request
  display and to show unavailable when no value exists.
- 16:9 behavior on physical devices and with platform font scaling; the local
  regression uses a fixed 360×640 logical viewport.
- Real Supabase recovery email delivery, redirect allowlists, and Android/iOS
  callback behavior.
- Direct browser UI automation for every screen.
- Production load and concurrency behavior.

These gaps are carried into [`08-test-summary-report.md`](08-test-summary-report.md).
