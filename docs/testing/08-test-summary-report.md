# Test summary report

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Outcome

**Local automated checks pass; the full authenticated demo remains to be verified.**

| Check | Current result |
|---|---|
| Backend unit/router | 30 passed; one DB test ignored |
| Flutter analyzer | Clean |
| Flutter unit/widget | 62 passed |
| Dedicated DB integration | Not run this cycle |
| HTTP smoke script | PASS: 200/200/401/404 with expected JSON fields |
| Target schema metadata | New trip/notification and commute schema present |
| Linux/web builds | Not rerun this cycle |
| Authenticated user flows | Not run; account warning remains open |

## Results by testing step

### 1. Unit testing

Module/model/widget assertions and analysis pass in the recorded package runs.
The 30 backend and 62 Flutter totals include component tests; they are combined
suite counts, not independently measured unit-only totals.

### 2. Integration testing

HTTP/JWKS/provider stand-ins and client-contract checks pass within those suites.
Schema inspection confirms current feature metadata. The dedicated migration,
CRUD and ownership database test was not run in this cycle, so this stage remains
incomplete.

### 3. System testing

Running-backend smoke passes all four HTTP/JSON checks. Release builds were not
rerun, and authenticated app/device flows remain unverified. The reported account
banner remains open; backend smoke alone does not complete this stage.

## Demo scope

Auth/recovery, profiles, trips/history, saved places/routines, maps/geocoding,
provider routing, conditions, assistant and inbox features are implemented.
Home includes an opt-in demo prediction display. Trained inference, forecast
accuracy and push delivery are outside this cycle. Public transit needs OTP
and Jakarta GTFS configuration; live incident-feed and recovery behavior need
separate verification.

## Interpretation

Tests exercise component fixtures and stand-ins. Some runtime paths use different
configuration, so passing suites establish their tested boundary rather than
complete live-system behavior. Imported 32/72 counts and build/integration passes
are historical docs-branch results, not main results.

## Before presentation

1. Resolve or reproduce INC-001 with an authenticated request trace.
2. Confirm the device reaches the configured API.
3. Run the visible scripts and retain evidence under `testing/evidence/`.
4. Walk through sign-in, trip persistence, Home display, assistant and inbox.
5. Record unavailable external services and any device layout issues.

No production acceptance or ML accuracy conclusion is made by this demo cycle.

## Timeout-fix verification — 2026-11-09

Changes after the recorded `3fbc286` baseline:

1. **Unit testing:** backend 33 passed/one DB case ignored; Flutter 66 passed;
   analysis clean. Added stalled refresh/header/body tests, late-auth write
   prevention, upload/trip timeout mapping, JWKS failure handling and immediate
   alert-queue acknowledgement.
2. **Integration testing:** dedicated local database suite passed, including
   authenticated avatar PNG upload and confirmed-trip persistence. Evidence:
   `testing/evidence/db-20261109T072105086787Z/integration.log`.
3. **System testing:** rebuilt backend and Flutter hot restart completed. The
   desktop session refreshed; authenticated profile/trip reads returned 200 in
   approximately 0.4 seconds. HTTP smoke passed 200/200/401/404. User-visible
   upload/trip retry confirmation is still pending; no complete system pass yet.

Combined-suite evidence: `testing/evidence/20261109T072211984744Z/`.
Auth calls now have a 5-second transport deadline and a 6-second token wait.
JWKS verification has a 4-second overall budget (3-second upstream HTTP);
DB pool acquisition is 4 seconds, statements 6 seconds and locks 3 seconds.
Inbox reads no longer run provider evaluation; manual evaluation acknowledges
asynchronously. Account errors retain their cause and save timeouts advise
checking persisted state before retrying.

## Provider freshness and route-map verification — 2026-11-09

1. **Unit testing:** backend 34 passed/one DB case ignored, Flutter 68 passed,
   analyzer clean. Coverage includes closest BMKG/Open-Meteo valid-time selection,
   CAMS fallback and old-data rejection, route endpoints/intermediate geometry,
   and years-old cache rejection. Combined-suite evidence:
   `testing/evidence/20261109T074916548991Z/`.
2. **Integration testing:** provider HTTP fixtures pass. Live recency audit found
   nearby OpenAQ station metadata ranging from 2016 through today; current stations
   are now selected before inactive ones. Public Open-Meteo weather and CAMS
   returned current-day values. The BMKG sample request returned an HTTP error;
   live BMKG availability is not claimed.
3. **System testing:** backend rebuilt and desktop app restarted. Authenticated
   conditions GETs at three Jakarta points returned available Open-Meteo weather
   valid at 2026-11-09 15:00 WIB and OpenAQ PM2.5 valid at 14:00 WIB. Inspect the
   actual presentation-device route labels manually; sampled geometry does not
   establish continuous coverage or street-level model precision.

Scripts: `testing/scripts/provider_freshness.py` and
`testing/scripts/conditions_smoke.py`. The latter reads the local desktop session
and prints source/time metadata only. BMKG requires a matching optional adm4;
route samples without one use Open-Meteo. CAMS global resolution is about 45 km.

## Public transportation — 2026-11-16

1. **Unit testing:** full backend suite: 39 passed, three ignored resource-dependent
   cases. Full Flutter suite: 73 passed; analysis clean. New coverage includes
   GTFS calendars/exceptions, frequency and exact service, times after midnight,
   transfer/pickup restrictions, quoted CSV, and itinerary parsing/UI.
2. **Integration testing:** mock Commute API verifies matching vehicle IDs at
   boarding/alighting stations (and ignores the origin's terminus arrival time).
   Supplied Transjakarta feed test passed for Blok M–Kota: 576 usable patterns,
   GTFS shape geometry. Explicit live Commute API test passed for Gondangdia–Depok
   using station timetables and a provider fare of Rp 4000. API-outage fixture
   retains a valid local bus alternative.
3. **System testing:** rebuilt/restarted the local backend and hot-reloaded Flutter.
   `python3 testing/scripts/transit_smoke.py` passed authenticated bus and rail
   requests through `/api/mobility/plan`, without saving trips. Bus used
   `transjakarta_gtfs`; rail used `commute_shiorilabs`. Actual device confirmation,
   saved-transit history reload and accessibility/visual review remain manual.

Three ignored checks are intentionally separate: dedicated DB test, user-provided
feed test, and live public API test. Database runners now filter the DB test by
name rather than invoking every ignored resource-dependent case.

Source/setup/limits: [public transport contract](../../backend/docs/public-transport.md).
Bus shapes are from GTFS. Walking links and API rail station connections are
explicitly schematic. Frequency and walking times are estimates, not live vehicle
positions. API fares are displayed when available; local GTFS fare computation is
not implemented. OTP is no longer required for the default two-source planner.

## Multiple transit options and named route conditions — 2026-11-16

1. **Unit testing:** backend 40 passed, four resource-dependent checks ignored;
   Flutter 76 passed; analyzer clean. Coverage includes operator-diverse station
   candidates, independent bus/KRL selection despite a shared transport mode,
   separate route metrics/geometry, legacy response compatibility, named endpoints
   and intermediate addresses, and geocoder-failure fallback without losing readings.
2. **Integration testing:** local HTTP plus GTFS fixture retains both valid bus
   and rail journeys. Explicit supplied-feed/public-API Monas–UI test passed:
   KRL via Juanda to Universitas Indonesia or Pondok Cina, and Transjakarta 9D
   plus 4B via Sari Pan Pacific–Santo Lukas–STT NF. Distinct ride sequences remain
   available even when slower; identical sequences are deduplicated.
3. **System testing:** rebuilt/restarted backend and restarted the running Flutter
   demo. Authenticated `transit_smoke.py --case monas-ui` passed and returned all
   three alternatives without saving a trip. Device interaction, visual review
   of resolved street names, and saved-trip history acceptance remain manual.

Current suite evidence: `testing/evidence/20261116T000441310893Z/`, including
`transit-monas-ui.log`. The fourth ignored check is the new Monas–UI resource
integration test; it was executed explicitly. Schedules/frequency estimates vary
by request time; options require eligible service and supported walking access.

## Real publisher news and Python/PyTorch forecasts — 2026-11-16

1. **Unit testing:** backend 41 passed (four resource-dependent cases ignored),
   Flutter 80 passed, Python eight passed, analyzer clean. Checks cover forecast
   expiry/location/range validation, UI model outputs and outages, chronological
   target splits, saved-weight inference, stale/gap rejection, hourly cache
   rollover, RSS publication dates/trusted links, and dateline-only rejection.
2. **Integration testing:** the isolated database test passed publisher-news
   deduplication, opt-out preferences and per-user ownership assertions. Evidence:
   `testing/evidence/db-20261116T035642809715Z/`. Real provider-history training
   used 60 days at five Jakarta-region points with separate chronological
   validation/test periods; metrics and provenance are in
   `ml/artifacts/model_card.json`. Test MAE: temperature 0.96°C, rain 0.21 mm,
   PM2.5 18.46 µg/m³, AQI 5.29; targets are provider model history.
3. **System testing:** Python service and backend started; scheduled in-app
   checks enabled for the running backend. Linux demo built and launched.
   Authenticated live checks returned 12 PyTorch hours and current ANTARA
   reports; four publisher reports appeared in the account inbox. An initial
   expired session was refreshed by the app. A subsequent hour-boundary cache
   issue was reproduced and fixed; the dedicated Python regression passes.
   Actual device interaction, reader-link opening and mobile visual acceptance
   remain manual; Linux launch and widget checks do not complete those cases.

Combined evidence: `testing/evidence/20261116T035642819550Z/`; the Python log was
updated after the hour-boundary regression was added. `intelligence-system.json`
records the final authenticated provider/inbox check. News uses original publisher
publication/expiry dates, links and area-level relevance, without treating article
presence as a verified current incident. Traffic ML is unavailable pending a
validated historical traffic dataset. Model results are experimental regional
estimates and do not replace current-condition hazard evidence.

Setup, training, API contract and limitations: [ML and news documentation](../../ml/README.md).

## Route-grounded Gemini and news severity preferences — 2026-11-16

1. **Unit testing:** 45 backend tests passed (four resource-dependent cases
   ignored), 84 Flutter tests passed, nine Python tests passed, analyzer clean.
   Coverage includes bounded route selections, server-only Gemini evidence,
   unavailable signals, incomplete provider replies, explicit UTC→WIB fields,
   selected-mode/account handoff, severity ordering/classification, and filter
   save failure rollback. Source context is refreshed for each question.
2. **Integration testing:** isolated database run passed the additive severity
   migration, partial preference persistence, owned-route isolation, delivery
   minimums, server filtering before pagination, independent non-news alerts,
   and severity reclassification preserving original read/sent state. Evidence:
   `testing/evidence/db-20261116T043236454912Z/`.
3. **System testing:** applied the additive preference migration to the demo,
   restarted backend/Python and hot-restarted Linux. The live assistant smoke
   submits a public Monas–UI KRL selection, verifies three coordinate-specific
   server lookups and performs read-only severity-query/preference checks. It
   records the real Gemini engine/model, response, sources and valid times in
   `assistant-live.json`. Manual device review of choosing another route, changing
   switches, links and visual/accessibility behavior remains outstanding.

Combined evidence: `testing/evidence/20261116T043236475945Z/`. The Python log was
refreshed after additional collision/negation classifier assertions. Legacy client
measurements cannot override server facts; routes remain plan estimates, forecasts
remain experimental, and news severity is an app classification. Critical RSS
severity is not inferred. Profile controls are active and revert failed saves;
news minimums apply to delivery and inbox queries without filtering weather/AQI
alerts. The numbered 00–08 documentation and three testing stages are preserved.

Contract and demonstration steps: [assistant and alerts](../../backend/docs/assistant-and-alerts.md).

Final live verification used the real Gemini engine with Monas–UI, provider
valid times and WIB forecast labels. `severity-filters-live.json` records inbox
threshold counts after refreshing current publisher classifications.

## Delete read and immediate alert preference updates — 2026-11-16

1. **Unit testing:** backend 45 passed (four resource-dependent cases ignored),
   Flutter 88 passed, Python nine passed, analyzer clean. The reproduction changes
   preferences externally while Alerts remains mounted, verifies old low news
   disappears before the delayed reload completes, and checks counts/switches.
   Added deletion checks cover read vs unread, repeated clicks and failures.
2. **Integration testing:** disposable DB run passed the additive dismissal
   migration, saved preference floors even with an explicit stale `low` query,
   hiding previously delivered disabled types, delete-read ownership/idempotency,
   preserving unread/other users' items, and keeping dismissed reports hidden
   after severity reclassification. Evidence:
   `testing/evidence/db-20261116T045230729648Z/`.
3. **System testing:** apply the migration and reload the demo; the read-only
   `alerts_smoke.py` checks actual preference-filtered list reads and unauthenticated
   deletion protection. It does not delete the real account's alerts. Manual
   presentation-device deletion/settings review remains separate from widget/API
   evidence. API/UI verification results are retained under the combined path.

Combined evidence: `testing/evidence/20261116T045337770588Z/`. Current inbox
visibility follows saved settings, including existing items; lowering restrictions
reloads eligible existing items. Delete read uses a retained event-key dismissal
so background checks cannot bring removed alerts back. Documentation remains
numbered 00–08 with unit, integration and system testing as its three stages.

Live read-only check passed after migration/reload: both inbox APIs applied the
account's saved Medium minimum, and unauthenticated Delete read returned 401.
Evidence: `testing/evidence/20261116T045337770588Z/alerts-live.json`. No actual
demo inbox deletion was performed.

## Unread actions and visible inbox toolbar — 2026-11-16

1. **Unit testing:** backend 46 passed (four resource-dependent cases ignored),
   Flutter 91 passed, Python nine passed; analyzer clean. Deletion is reproduced
   using unmodifiable service snapshots: it succeeds, clears local rows and
   reloads without an Unsupported operation error. Phone widgets verify visible
   Mark all read/Delete read buttons, individual toggles, checkbox selection,
   selected-unread success and failure/retry. The authenticated client test
   exercises real payload/response handling for all read-state actions.
2. **Integration testing:** isolated DB run passed single/bulk unread ownership,
   mixed-owner atomic rollback, bounded/unique IDs, idempotency, deleted-record
   protection and preference-aware bulk read. It also retained prior dismissal,
   threshold and reclassification checks. Evidence:
   `testing/evidence/db-20261116T051025586576Z/`.
3. **System testing:** rebuilt/restarted the backend and hot-restarted the running
   app. Read-only smoke checks passed authentication protection for read/unread/
   deletion endpoints plus saved preferences on actual inbox reads. No live
   account read flags or alerts were changed by the smoke. Manual presentation
   device interaction remains separate from phone-widget/API verification.

Evidence: `testing/evidence/20261116T051232949340Z/`, including `alerts-live.json`.
The bulk toolbar is visible below the header, replacing the previous overflow
menu. Existing alerts can be selected with checkboxes and marked unread together;
individual read/unread controls remain available. No new migration is required.
