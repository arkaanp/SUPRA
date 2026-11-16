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
  transit defaults to the local Transjakarta GTFS plus the public Commute Data API.
  See [public transport](public-transport.md) for timing, geometry, and setup.
* `/api/alerts/evaluate`: POST checks the caller's due routines/current trips.
  Responds with HTTP 202 Accepted `{"queued": true, "news_configured": bool, "scheduler_enabled": bool}`
  and evaluates asynchronously. Repeated evaluation is deduplicated, respects profile
  and routine preferences, and refuses stale environmental readings as current hazard evidence.
* `/api/trips/{id}/finish`: PUT / POST ends current-trip alert eligibility, retaining history.

The opt-in alert worker evaluates a bounded batch every minute when `ALERTS_ENABLED=true`;
each target is checked at most every five minutes. Notifications are in-app inbox messages,
not push deliveries. News defaults to current ANTARA RSS through the Python
intelligence service (`INTELLIGENCE_URL`, default http://127.0.0.1:8001). News
keeps original publication/expiry dates and links, uses explicit area-level
matching, respects preferences and deduplicates article IDs. A trusted custom
JSON incident feed remains optional via `NEWS_INCIDENTS_URL`.

Authenticated `GET /api/forecast/hourly?latitude=...&longitude=...` returns live
Python/PyTorch inference for the next 12 hours: temperature, precipitation, PM2.5,
AQI and wet-hour probability, with model ID, training/validation provenance and
input freshness. Home and Trip ML controls consume these values. Traffic ML is
unavailable pending a validated training dataset. Forecasts remain separate from
current-condition hazard evidence. See [ML and news setup](../../ml/README.md).

## Password Recovery Configuration

1. **Email Template (Linux / Web Code Flow)**:
   In Supabase Auth settings under Email Templates -> Reset Password, include `{{ .Token }}`
   in the template body so Linux desktop and browser users can copy the 6-digit OTP code into
   the app's recovery screen.
2. **Deep Link Callbacks (Android / iOS / Web)**:
   Add `io.supabase.supra://login-callback` and your Web URL to the Supabase Redirect URLs
   allowlist. Android and iOS application manifests/plists are configured to capture this scheme.

## Route-aware Gemini and news severity

See [assistant and alert preferences](assistant-and-alerts.md) for selected-route
context, server-fetched evidence, the additive preference migration, delivery
thresholds, severity-filter queries and verification commands. Alert preferences
are active and account-scoped; profile and inbox controls auto-save them.
