# Commute feature contract

All `/api` endpoints below require the existing Supabase bearer token. Ownership
is taken from its verified subject, never from a request's user ID.

* `/api/places`: GET list / POST create; `/api/places/{id}`: PUT full replacement /
  DELETE. Fields: label, kind (home/work/school/custom), latitude, longitude.
* `/api/routines`: GET / POST; `/api/routines/{id}`: PUT full replacement / DELETE.
  Fields: label, origin_id, destination_id (owned place IDs), mode (car,
  motorcycle, walk, public_transit), weekdays (Monday=0), departure_minute (0–1439),
  timezone (initially Asia/Jakarta), lead_minutes (5–180), enabled, alerts_enabled,
  news_enabled. These are subscriptions, not traveled history.
* `/api/mobility/plan`: POST origin/destination `{latitude,longitude}`, mode.
  Returns actual provider geometry, duration, distance, steps, provenance; no
  synthetic route on failure. Walking/motorcycle use Valhalla mode profiles;
  transit uses a configured OTP 2.x GTFS GraphQL endpoint with Jakarta data.
* `/api/alerts/evaluate`: POST checks the caller's due routines/current trips.
  Responds with HTTP 202 Accepted `{"queued": true, "news_configured": bool, "scheduler_enabled": bool}`
  and evaluates asynchronously. Repeated evaluation is deduplicated, respects profile
  and routine preferences, and refuses stale environmental readings as current hazard evidence.
* `/api/trips/{id}/finish`: PUT / POST ends current-trip alert eligibility, retaining history.

The opt-in alert worker evaluates a bounded batch every minute when `ALERTS_ENABLED=true`;
each target is checked at most every five minutes. Notifications are in-app inbox messages,
not push deliveries. News requires a configured trusted JSON incident feed (`NEWS_INCIDENTS_URL`).
Feed items contain id, title, source_url (HTTPS), latitude, longitude, published_at,
starts_at, expires_at, and verified=true. Events expire and are matched against
actual route geometry when available, otherwise only near the endpoints.

Forecast UI reserves separate temperature, AQI and weather fields for future ML
output. Missing values remain empty; source observations are not extrapolated.

## Password Recovery Configuration

1. **Email Template (Linux / Web Code Flow)**:
   In Supabase Auth settings under Email Templates -> Reset Password, include `{{ .Token }}`
   in the template body so Linux desktop and browser users can copy the 6-digit OTP code into
   the app's recovery screen.
2. **Deep Link Callbacks (Android / iOS / Web)**:
   Add `io.supabase.supra://login-callback` and your Web URL to the Supabase Redirect URLs
   allowlist. Android and iOS application manifests/plists are configured to capture this scheme.
