# 03 — Test Case Catalog

| Field | Value |
|---|---|
| Test case set ID | `TCS-2026-11-09-01` |
| Test cycle | `TC-2026-11-09-01` |
| Branch / commit | `main` @ `967a477` |
| Date | 2026-11-09 |

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## 1. Conventions

- **P0** — release blocker; must pass before any deployment.
- **P1** — core user flow; must pass or be explicitly blocked.
- **P2** — important regression or resilience case.
- **PASS** — executed and met expected result.
- **PARTIAL** — related assertions passed; the full case was not exercised.
- **NOT RUN** — not executed in this cycle.
- **BLOCKED** — requires an unavailable external dependency or approved configuration.

Common preconditions:

- The repository is at the commit above.
- Commands run from `backend/` or `mobile/` as indicated.
- Integration tests use a disposable PostgreSQL database whose name ends in
  `_test`; no application database is used.
- No secrets, tokens, account emails, or private configuration are printed.

## 2. Backend unit cases

| ID | Scenario | Expected result | Priority | Status |
|---|---|---|---|---|
| `UB-001` | Request with missing, malformed, expired, wrong-issuer, wrong-audience, or wrong-role token | Rejected with 401; valid token injects verified subject | P0 | PASS |
| `UB-002` | Authenticated user supplies another user's ID in a path | Rejected; no impersonation | P0 | PASS |
| `UB-003` | Confirmed trip with missing, non-finite, or out-of-range coordinates | 400; trip is not persisted | P0 | PASS |
| `UB-004` | Route waypoints empty, non-array, missing lat/lng, non-finite, extra keys, or over 1000 points | 400 with JSON error; no panic | P1 | PASS |
| `UB-005` | Row not found, constraint violation, pool failure | 404/400/409 as appropriate; internal details hidden in 500 | P1 | PASS |
| `UB-006` | Conditions query outside service envelope or malformed `adm4` | 400 with explicit message | P1 | PASS |
| `UB-007` | Weather provider outage while air/traffic are healthy | Weather marked unavailable; other signals retained | P0 | PASS |
| `UB-008` | Provider credentials absent or provider returns bad response | Explicit unavailable/error signal in adapter fixtures | P0 | PASS |
| `UB-009` | Provider 401/403/429, malformed body, oversized body, timeout | Sanitized failure state; no credential or URL leakage | P1 | PASS |
| `UB-010` | Due window at WIB midnight and across weekdays | Correct UTC departure; non-selected weekday returns none | P0 | PASS |
| `UB-011` | Signal is stale or a provider forecast | Not accepted as current hazard evidence | P0 | PASS |
| `UB-012` | PM2.5, rain, and traffic thresholds; low traffic confidence | Hazards detected at/above thresholds; low confidence ignored | P0 | PASS |
| `UB-013` | Incident feed record is unverified, expired, non-HTTPS, out of area, or off-corridor | Invalid records rejected; valid nearby records relevant | P0 | PASS |
| `UB-014` | Polyline with valid, truncated, or invalid characters | Valid geometry decoded; invalid input rejected | P1 | PASS |
| `UB-015` | OTP response with no transit leg or broken shape | Rejected; explicit unavailable itinerary | P0 | PASS |
| `UB-016` | Avatar upload with filename only, signature only, non-image, oversized, or valid image | Invalid rejected; valid decoded, resized, re-encoded PNG | P1 | PASS |
| `UB-017` | Agent request contains credentials/invalid history; Gemini is unavailable | Request rejected or 503; no simulated environmental answer | P0 | PASS |
| `UB-018` | Health readiness with reachable, closed, or slow pool | 200 only when DB is ready; bounded acquisition | P1 | PASS |
| `UB-019` | Unknown route, wrong method, protected route without auth | JSON 404, JSON 405 with `Allow`, 401 before method handling | P1 | PASS |
| `UB-020` | Valhalla and OTP real HTTP stand-ins | Mode-specific geometry/duration parsed; failures explicit | P0 | PASS |
| `UB-021` | Chat message outside commute/environment scope, including prompt-injection phrasing | Deterministic refusal with `scope-guard`; provider is not called | P1 | NOT RUN — branch-only regression coverage; not merged |
| `UB-022` | Chat condition context with valid values, AQI 501, or oversized status text | Bounded context accepted; out-of-range/oversized context rejected with 400 | P1 | NOT RUN — branch-only regression coverage; not merged |

## 3. Mobile unit/widget cases

| ID | Scenario | Expected result | Priority | Status |
|---|---|---|---|---|
| `UM-001` | Repeated failed sign-in and password visibility toggles | Password field remains editable; focus recoverable | P0 | PASS |
| `UM-002` | Recovery email request → code verification → password update | State transitions; recovery flag set/cleared; update completes | P0 | PASS |
| `UM-003` | Preference JSON round-trip including `alert_relevant_news` | All four flags preserved | P1 | PASS |
| `UM-004` | Notification JSON with and without `source_url`/`context.expires_at` | Fields parse; missing values remain null | P2 | PARTIAL — model implemented; no dedicated assertion |
| `UM-005` | Legacy trip JSON without `transport_mode`/`active_until` | Decodes with safe defaults | P2 | PARTIAL — legacy payload decodes; default not separately asserted |
| `UM-006` | Saved place and routine JSON round-trip | Labels, kinds, coordinates, weekdays, timezone, flags preserved | P1 | NOT RUN — no dedicated test |
| `UM-007` | Transport mode API values and labels | `car`, `motorcycle`, `walk`, `public_transit` map correctly | P1 | PARTIAL — car and recommendation modes covered |
| `UM-008` | Fresh PM2.5, AQI, rain, and traffic conditions | Outdoor/road penalties applied; duration unchanged; advice items generated | P0 | PASS |
| `UM-009` | Stale or missing environmental values | No current-risk penalty; incomplete coverage disclosed | P0 | PARTIAL — stale helper covered; recommendation stale case not dedicated |
| `UM-010` | Forecast tiles with live and missing data | `Temp —`, `AQI —`, `Weather —` are separate fields | P0 | PASS |
| `UM-011` | Aged conditions after partial failure | STALE labels; original timestamp retained; no value advancement | P0 | PASS |
| `UM-012` | Desktop map renderer | Geographic raster tiles requested; coordinate selection and zoom work | P0 | PASS |
| `UM-013` | Geocoding no-match, invalid coordinates, provider outage, late results | Distinct outcomes; stale/late results ignored | P1 | PASS |
| `UM-014` | Explicit map selection and pin editing | Old pin invalidated; late remote results do not overwrite | P1 | PASS |
| `UM-015` | Recovery password mismatch or shorter than 8 characters | Rejected with clear error; no password change | P1 | PARTIAL — length/state path implemented; mismatch assertion not dedicated |
| `UM-016` | Assistant page without a client API key | No key prompt; no fictional context | P0 | PASS |
| `UM-017` | Provider outage leaves only last-known values; one or more indicators missing | Rain, temperature, AQI, and traffic stay visible; missing values read `No data`; aged values read `STALE`; original observation time retained | P0 | NOT RUN — branch-only regression coverage; not merged |
| `UM-018` | Open Home with ML display off, then enable it with no model values | Off by default; enable and inspect demo indicators | P0 | NOT RUN — branch-only regression coverage; not merged |
| `UM-019` | Persist the ML preference and expose the same toggle on Trip | Stored value restored; Trip toggle appears with route output; no prediction shows `ML AQI unavailable` | P1 | NOT RUN — branch-only regression coverage; not merged |
| `UM-020` | Render Home, Assistant, Alerts, and Trip at 360×640 logical (16:9) | No `RenderFlex` overflow or clipped controls; Home location picker still opens | P0 | NOT RUN — branch-only regression coverage; not merged |
| `UM-021` | Send a chat message with the latest condition snapshot | AQI, weather, temperature, status, source, observed time, and stale flag are sent as labelled context | P1 | NOT RUN — branch-only regression coverage; not merged |

## 4. Integration cases

| ID | Scenario | Expected result | Priority | Status |
|---|---|---|---|---|
| `IN-001` | Apply all migrations twice to a fresh disposable `*_test` database | Both runs succeed; schema is idempotent | P0 | NOT RUN in current main cycle |
| `IN-002` | Cross-user reads/writes through the router | Application ownership checks return 404/empty; no data leak | P0 | NOT RUN in current main cycle |
| `IN-003` | Create/list/read profiles for two users | Each user sees only self; profile upsert works | P1 | NOT RUN in current main cycle |
| `IN-004` | Trip create/list/read/update/delete with two users | Cross-user access denied; lists scoped | P0 | NOT RUN in current main cycle |
| `IN-005` | Confirmed trip, active window, finish, account deletion | Confirmation/coordinates persist; finish is owner-only; deletion removes owned trips | P0 | NOT RUN in current main cycle |
| `IN-006` | Preferences defaults and partial updates | Defaults preserved; unrelated flags unchanged | P1 | NOT RUN in current main cycle |
| `IN-007` | Notification ownership, source/context, deduplication | Cross-user access denied; new fields round-trip; duplicate event key creates one row | P1 | NOT RUN in current main cycle |
| `IN-008` | Saved places create/list/update/delete with two users | Owner CRUD works; cross-user update/delete denied; list scoped | P0 | NOT RUN in current main cycle |
| `IN-009` | Routines create/list/update/delete with owned and cross-user places | Owned places required; cross-user create/update/delete denied; list scoped | P0 | NOT RUN in current main cycle |
| `IN-010` | Manual alert evaluation | HTTP 202 `{queued:true, news_configured, scheduler_enabled}`; no synchronous generation claim | P1 | NOT RUN in current main cycle |
| `IN-011` | Conditions endpoint with three-provider success and partial failure | Normalized signals; healthy signals retained; failures explicit | P0 | PASS |
| `IN-012` | Valhalla walking/motorcycle and OTP transit stand-ins | Provider geometry/duration parsed; wrong mode/non-transit rejected | P0 | PASS |
| `IN-013` | Agent provider missing or failing | 503 in backend unit-test configuration | P0 | NOT RUN in current main cycle |
| `IN-014` | Avatar upload validation and re-encoding | Invalid rejected; valid PNG output | P1 | PASS |
| `IN-015` | Mobile API client auth header, origin restriction, error mapping | Bearer token sent; redirects refused; API errors retain status/message | P1 | NOT RUN in current main cycle |
| `IN-016` | Unauthenticated protected route, unknown route, wrong method | 401, JSON 404, JSON 405 | P1 | PASS |
| `IN-017` | Verified-news evaluation for saved places | Unexpired incident within 3 km creates one notification per user/incident; outside-radius, expired, or unverified records are ignored | P1 | NOT RUN — branch-only regression coverage; not merged |

## 5. System cases

| ID | Scenario | Expected result | Priority | Status |
|---|---|---|---|---|
| `SY-001` | Start web/Linux app with approved configuration | Login or shell renders; no missing-config crash | P0 | NOT RUN — no live approved configuration in this cycle |
| `SY-002` | Sign in, sign out, expire session | Shell appears; state clears; re-auth required | P0 | NOT RUN |
| `SY-003` | Request recovery email, open link or enter code, set password | Recovery screen; password updated; normal sign-in works | P0 | NOT RUN — live email/redirect/deep link requires approved account |
| `SY-004` | Home with live then stale conditions; toggle ML display | Three separate forecast fields; indicators stay visible; STALE labels and original times; ML output unavailable rather than invented | P0 | NOT RUN — covered at widget level by `UM-010`/`UM-011`/`UM-017`/`UM-018` |
| `SY-005` | Plan car/walk/motorcycle/transit; select history item; confirm; toggle ML | Provider route or explicit unavailable message; provider route or unavailable state; ML chip unavailable without a prediction | P0 | NOT RUN |
| `SY-006` | Save/edit/delete places; create/edit routine; plan now | Ownership-safe CRUD; schedule/mode persisted | P1 | NOT RUN |
| `SY-007` | Queue alert check; open inbox; end current-trip alerts | Queued status, inbox items, source links, saved-place news, finish works | P1 | NOT RUN |
| `SY-008` | Update profile and avatar | Valid avatar served; invalid rejected | P2 | NOT RUN |
| `SY-009` | Disable network/provider during use | Inspect stale labels and available demo indicators | P0 | NOT RUN |
| `SY-010` | Open map on Linux desktop | Raster basemap renders; selection works | P1 | NOT RUN — desktop widget test passes |
| `SY-011` | Linux and web release builds | Both builds succeed | P0 | NOT RUN in current cycle; readiness alone checked |
| `SY-012` | Start compiled backend with isolated DB; check health/auth/fallback | live 200, ready 200, unauthenticated 401, unknown 404 | P0 | NOT RUN in current cycle; readiness alone checked |
| `SY-013` | Open Home, Assistant, Alerts, and Trip at a 16:9 phone ratio | No overlapping or clipped controls; indicators and toggles usable | P0 | NOT RUN — covered at widget level by `UM-020` |
| `SY-014` | Ask a commute question, then an unrelated request, in the Assistant | Relevant answer; inspect scope handling and displayed condition context | P1 | NOT RUN — manual scope and context check required |


## Current demo interpretation

Expected results are test-design targets. PASS refers to fixture/stand-in assertions,
not complete runtime acceptance. Home demo prediction display is a local calculation;
model accuracy is not assessed. Manual system cases must record observed behavior.
