# Supra Flutter app

This is the mobile package in the monorepo; Axum lives in `../backend/`.
Flutter is managed with **FVM** (`.fvmrc` uses the reference project's stable
channel). Use `fvm flutter` / `fvm dart`, not an unrelated system SDK.

## Run locally

1. Install/select the configured SDK with `fvm install`.
2. Copy `config/local.example.json` to `config/local.json` if it doesn't exist.
   Set `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `SUPRA_API_URL`. The Supabase
   project must match the backend. Local config is ignored by Git and is passed
   as build-time defines, not bundled as an asset. No secret/service-role keys,
   database passwords, or signing secrets belong here. Public keys are still
   readable in the compiled app; this configuration is not a secret store.
3. Prepare `../backend/.env`, then, from `backend/`, run
   `cargo run --locked -- migrate` followed by `cargo run --locked`.
   Back up existing data first: the auth migration removes password hashes.
   Use a server-only database role that bypasses RLS. See `../backend/README.md`.
4. From `mobile/`:

```sh
fvm flutter pub get
fvm flutter run --dart-define-from-file=config/local.json
```

`SUPRA_API_URL` defaults to `http://localhost:3000`. On Android use
`http://10.0.2.2:3000` for the emulator or `adb reverse tcp:3000 tcp:3000` with
localhost. A physical device needs a reachable LAN address or forwarding.
`0.0.0.0` is a server bind address, not a client destination. Use HTTPS in
production; Android cleartext HTTP is enabled only for debug. Rebuild after
changing defines.

## Supported behavior

- Supabase email/password registration, email confirmation, sign-in, restored
  sessions, token refresh and sign-out. With confirmation enabled, confirm the
  email and return to sign-in; the app doesn't require an email deep link.
- After login/session restoration, authenticated `POST /api/users` synchronizes
  the profile before loading data. All API calls send the current bearer token;
  no password, email or caller-selected user UUID is used to authenticate Axum.
- Saved trips load from `GET /api/trips`; create/delete uses the matching API.
  Departure is sent as UTC and displayed in local time. Trip edits and route
  editing are not exposed by this UI yet.
- Inbox displays up to the latest 100 alerts and persists read state. “Mark all
  read” applies to that loaded page, not unseen historical pages.
- Preferences are loaded/upserted and saved via the authenticated user endpoint.
  Failures are visible; switches only commit state after the backend succeeds.
- Account data is cleared across sign-out/user switches. Profile-load errors have
  retry/sign-out actions rather than falling back to invented data.

## Initial provider conditions

Home retains the original dashboard: location selector, teal conditions card,
12-hour forecast strip, and recent trips. It calls Axum's authenticated `/api/conditions/current`;
no provider credentials belong in the client. Weather uses Open-Meteo, falling
back to BMKG only when the primary is unavailable and a matching `adm4` is supplied.
BMKG results are labeled as upcoming forecasts, not current measurements.
OpenAQ displays nearby station PM2.5, distance, attribution and stale state;
it does not claim to compute US AQI/ISPU from a single reading. TomTom displays
the nearest road-fragment speed, not traffic density or a route ETA. Results
include source information and WIB timestamps; unavailable providers do not hide
healthy signals. Last-known readings are cached per account, exact location and
BMKG village code, including across restarts. A failed/partial lookup retains
those values as **STALE**, without changing observation/fetch timestamps. If no
real cached value exists, the card shows an empty state rather than a baseline.
There is no automatic paid-provider polling or simulated-value fallback.

Configure `OPENAQ_API_KEY` and `TOMTOM_API_KEY` in `../backend/.env`, restart
Axum, and pull down on Home to refresh. Missing keys retain labeled last-known
readings where present, otherwise show unavailable states. The original hourly
strip is reserved for future **ML predictions**; unpopulated slots say "ML pending"
and are never extrapolated from current or stale readings.
See `../backend/docs/current-conditions.md` for provider setup and limits.

## Routing and desktop maps

The Trip page uses successful OSRM **driving** geometry, distance and duration.
Its duration is not a live-traffic ETA. Failure shows an unavailable message; no
straight-line or invented route is substituted. Motorcycle/transit routing,
route-wide exposure and hourly forecasts are not connected. A nearby-road TomTom
sample is never extrapolated into a whole-journey traffic score.

Linux/desktop uses `flutter_map` with geographic raster tiles, markers, route
polylines and attribution. Canvas rendering is only an explicit test fixture.
`MAP_TILE_URL`, `MAP_ATTRIBUTION_TEXT` and `MAP_ATTRIBUTION_URL` are public build
defines for a licensed tile service. The default OSM endpoint is for modest,
policy-compliant interactive development use: review
https://operations.osmfoundation.org/policies/tiles/ before distribution. Do not
bulk-download/prefetch tiles. Public services have no uptime guarantee.

Typing uses local place suggestions; **press Enter/Search** for remote Nominatim
results, then select a result explicitly. Unknown queries have no invented places.
Remote search/reverse lookups are cached/serialized, not autocomplete requests.
Set `GEOCODING_BASE_URL` to your compatible hosted service/proxy for deployment;
per-device throttling alone does not enforce a fleet-wide provider quota. Review
https://operations.osmfoundation.org/policies/nominatim/. `OSRM_BASE_URL` similarly
selects a compatible driving service; the public demo endpoint is not an SLA.

History contains backend-confirmed events with real coordinates and server
timestamps. The new migration preserves old planned trips but does not relabel
them as traveled journeys or import the ambiguous legacy shared-device cache.

## Assistant

Set `GEMINI_API_KEY` and `GEMINI_MODEL` only in `../backend/.env`, then restart
Axum. There is no in-app key prompt, direct Google fallback, simulated reply, or
hardcoded live context. Chat history is session-scoped and clears at logout/user
change. Remove any old Gemini entries from `config/local.json`; rotate keys if
previous binaries containing them were distributed.

## Commute features, advice & alerts

- **Password recovery**: Available on both Login and Profile screens. Supports
  email request, 6-digit OTP code verification, and password updating. Web and
  mobile deep linking capture `io.supabase.supra://login-callback`.
- **Saved places & routines**: Create and edit Home, Work, School, and Custom
  places. Configure daily routines with departure minute (WIB), weekdays, lead
  times, and alerts/news preferences.
- **Multimodal routing**: Supports Car, Motorcycle, Walking (via Valhalla), and
  Public Transit (via OpenTripPlanner).
- **Commute recommendations**: Compares provider routes and scores them using
  explicit preferences for duration, outdoor exposure (PM2.5 / AQI and rain),
  and nearest-road congestion without modifying provider ETAs. Provides advice
  on protective clothing, respirators, rain gear, and buffer times.
- **Alerts**: In-app notifications for environmental hazards and verified news
  incidents along journey corridors. Supports ending current-trip alerts and
  queueing manual checks against due routines.

**Future work**: ML prediction pipeline integration for upcoming forecast hours.
Push notifications (alerts are currently in-app inbox items).

Axum requires ES256/RS256 access tokens signed by the project's JWKS; HS256
projects need a signing-key migration. Deleting an app profile is not deletion
of a Supabase Auth account. Existing app-only UUIDs must be migrated explicitly,
never automatically linked to accounts by email.

## Checks

```sh
fvm flutter analyze
fvm flutter test
fvm flutter build web --dart-define-from-file=config/local.json
```

Tests use local HTTP stand-ins, image fixtures and fake Supabase responses, not
real provider credentials. For a live smoke
test, register and confirm a user, sign in, save a trip, reload to verify
persistence, change preferences, sign out and sign into a second account to
verify isolation. Backend cross-user DB tests require a dedicated test database.
