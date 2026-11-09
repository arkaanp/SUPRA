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
