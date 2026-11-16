# Test log

> Current demo baseline: `main` application commit `967a477` (2026-11-09).
> Documentation imported from `docs/testing`; application changes on that branch
> are excluded. Results below distinguish current checks from earlier branch evidence.

## Current main verification — 2026-11-09

Application baseline: `967a477`, Linux, local configured FVM SDK and Cargo.

| ID | Testing step | Check | Result |
|---|---|---|---|
| TL-001 | 1. Unit + 2. component integration (combined suite) | `cargo test --locked --offline` | 30 passed, 0 failed, one ignored database test |
| TL-002 | 2. Integration | Dedicated database integration | NOT RUN; no dedicated test URL configured |
| TL-003 | 1. Unit (supporting analysis) | `fvm flutter analyze` | No issues found |
| TL-004 | 1. Unit + 2. component integration (combined suite) | `fvm flutter test --no-pub` | 62 passed, 0 failed |
| TL-005 | 3. System (build preparation) | Linux/web release builds | NOT RUN in this cycle |
| TL-006 | 3. System (process smoke) | `python3 testing/scripts/smoke.py` | PASS: JSON live 200, ready 200, trips 401, unknown route 404 |
| TL-007 | 2. Integration (supporting metadata) | `python3 testing/scripts/schema_audit.py --backend-env` | Trip/notification feature columns; saved_places, routine_trips, alert_decisions present |
| TL-008 | 3. System (end-to-end) | Authenticated full application demo | NOT RUN; account warning reported by user |

Initial restricted runs hit local socket and SDK-cache permissions; checks were
rerun with the required environment access before the successful results above.

## Imported branch history

The docs branch recorded 32 backend passes, 72 Flutter passes, a disposable DB
integration pass and Linux/web build successes on its own application revision.
These are historical branch results and are not evidence for main. The original
records remain accessible in `git show docs/testing:docs/testing/06-test-log.md`.

## Reproducible evidence

Run `python3 testing/scripts/run_checks.py`. Each execution retains complete
suite logs and `summary.json` under `testing/evidence/` with commit, working-tree
state and exit codes. Counts can change when tests are added; record actual output.

| New run | Revision | Case/command | Result | Evidence |
|---|---|---|---|---|
| Pending | — | Manual authenticated warning reproduction | NOT RUN | — |

## Visible runner verification

The new runner completed with exit 0: backend 30 passed/one ignored, Flutter
62 passed, analyzer clean. Local raw evidence:
`testing/evidence/20261109T062032565183Z/`.
The HTTP smoke passed all four JSON/status checks. Schema audit showed five
successful migrations through `20261109000000` and the expected feature schema.
See [shareable results](../../testing/RESULTS.md).

## Stage outcome

1. **Unit testing:** executed package suites and analysis passed.
2. **Integration testing:** component stand-ins and schema inspection passed;
   dedicated database test NOT RUN.
3. **System testing:** backend smoke passed; builds and authenticated device
   flows NOT RUN. No complete system-stage pass is claimed.

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

## Route sample presentation update — 2026-11-09

- Detailed route samples moved below transport cards in the existing scroll view.
- Map labels replaced with compact transparent category-colored squares and rain
  symbols/mm. Zero rainfall and missing weather have distinct symbols.
- Provider AQI uses the shared AQI categories. Raw PM2.5 uses explicitly labelled
  concentration bands without deriving a numeric AQI. Missing air values are gray.
- Focused UI regression suite: 28 passed, covering category colors, scrolling,
  precipitation markers, geographic map behavior and location selection.

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
