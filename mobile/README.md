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

**Not available yet:** live conditions, route generation, forecast orchestration,
map overlays, saved locations, Agent 1 chat, automatic Agent 2 alerts, and push
delivery. The app explicitly shows these limitations; it does not seed mock
forecasts or notifications. Retained map/forecast widgets are reference UI only.

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

Tests use fake HTTP/Supabase responses, not real credentials. For a live smoke
test, register and confirm a user, sign in, save a trip, reload to verify
persistence, change preferences, sign out and sign into a second account to
verify isolation. Backend cross-user DB tests require a dedicated test database.
