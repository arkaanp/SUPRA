# Real-data migration contract

## Trips

`POST /api/trips` keeps the planned-trip fields and accepts four optional numeric
fields: `start_latitude`, `start_longitude`, `destination_latitude`,
`destination_longitude`. Supply all four together. `confirmed: true` requires
coordinates and records server time in `confirmed_at`. Responses include these
nullable fields. Existing planned trips are preserved, not backfilled as journeys.
History is a per-user projection of confirmed events; repeat confirmations count
as separate events. Deletion uses the existing ownership-checked trip endpoint.
No ambiguous legacy shared-device cache is imported.

## Assistant

`POST /api/agent/chat` accepts message, bounded history, and optional user context.
Client API-key overrides are rejected. Credentials and the configured model belong
only in backend environment variables. Success has `simulated: false`; missing
configuration, provider failures, timeouts and malformed responses return 503.
There is no generated offline substitute. Context is user-supplied, not verified
live measurement evidence.

## Route and conditions display

Only successful driving-provider geometry/distance/duration may be displayed as a
driving route. No synthetic geometry, motorcycle distance scaling, guessed transit
schedule or traffic-adjusted ETA is substituted. Until mode-specific routing is
configured, motorcycle/transit are unavailable rather than driving aliases.
OSRM duration is a routing estimate, not a live traffic ETA.

Environmental consumers reuse `GET /api/conditions/current` (see
`current-conditions.md`). Missing/stale/forecast values remain distinguishable.
PM2.5 is not multiplied into AQI. Location samples and nearest-road flow must not
be described as route-wide exposure, citywide measurements or future predictions.
No-data does not mean zero rain, clean air or free-flow traffic.

The client retains genuine last-known values per account/location/village on
refresh failures, including across restarts. They remain visibly **stale** with
their original observed/fetched times; stale values are not current safety
evidence. With no cached value, the original dashboard uses an empty state. Its
original hourly strip is reserved for future ML predictions, not generated
diurnal curves or repeated stale observations masquerading as predictions.
