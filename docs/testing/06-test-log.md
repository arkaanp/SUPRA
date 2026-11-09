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
