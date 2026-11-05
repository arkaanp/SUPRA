# Location conditions — initial provider contract

`GET /api/conditions/current?latitude=-6.2&longitude=106.82`

Requires the same Supabase bearer token as other resource endpoints. No profile
or database write is needed. Coordinates must be within the initial Greater
Jakarta bounding box: latitude [-6.9, -5.8], longitude [106.3, 107.3]. This box
is a service envelope, not an administrative-boundary polygon.

Optional `adm4=31.71.03.1001` supplies a BMKG village code. The caller must
choose the matching village; this endpoint does not reverse-geocode coordinates.
Unknown query fields, malformed codes and invalid coordinates return JSON 400.

## Response

200 means the aggregate lookup completed, **not** that every signal is available.
Each of `weather`, `air_quality`, and `traffic` has:

| Field | Meaning |
| --- | --- |
| `status` | `available`, `stale`, or `unavailable` |
| `source` | `open_meteo`, `bmkg`, `openaq`, or `tomtom` |
| `kind` | `model_estimate`, `provider_forecast`, `station_observation`, `provider_live_estimate`; null if unavailable |
| `valid_at` | UTC observation/forecast valid time; null when unknown/unavailable |
| `message` | Attribution/limitations or a sanitized failure reason |
| `data` | Source-normalized object below; null if unavailable |

Top-level `latitude` and `longitude` echo the requested point. `retrieved_at`
is UTC time when the aggregate lookup finished, not a measurement time. Times
are rendered as WIB in Flutter. Each signal can have a different valid time.

- **Open-Meteo weather:** `temperature_c`, `humidity_percent`,
  `precipitation_mm`, `interval_seconds`, `wind_speed_kmh`, `weather_code`,
  `model_latitude`, `model_longitude`. Precipitation belongs to the returned
  provider interval, not a probability or a daily total. This is model-derived
  current weather, not a thermometer/rain-gauge observation. Estimates older
  than two hours or implausibly future-dated trigger fallback.
- **BMKG fallback weather:** `temperature_c`, `humidity_percent`, `description`,
  `issued_at`, `village`, `model_latitude`, `model_longitude`. Used only if the
  primary weather request fails, is malformed, or is stale, and `adm4` is given.
  Returns the first upcoming forecast within six hours from a run issued within
  24 hours. **Not a substitute current observation**: `kind=provider_forecast`
  and its actual valid time must remain visible. No fabricated rain probability.
  The returned village code must match and its representative point must be
  within 15 km; that sanity check does not prove point-in-village membership.
- **OpenAQ air quality:** `pm25_ug_m3`, `station_id`, `station_name`,
  `distance_km`, `coordinates`, `provider`, `owner`, `licenses`. Discovers up to
  100 locations within 25 km, examines the nearest three stationary candidates,
  joins `/locations/{id}/latest` by sensor ID to parameter/unit metadata, and
  selects a usable PM2.5 reading. Prefers a fresh station; reports stale readings
  (>3 hours old) explicitly. No reading is a valid unavailable outcome. Coverage
  is limited to those candidates, not an exhaustive search of every sensor.
  **No US AQI or ISPU is computed from an instantaneous PM2.5 value.**
  Keep station distance, source and license attribution visible. This is not an
  exact-point or street-wide measurement and is not used to assess health risk.
- **TomTom traffic:** `speed_kmh`, `free_flow_speed_kmh`,
  `travel_time_seconds`, `free_flow_time_seconds`, `confidence`, `road_closed`,
  `coordinates` (provider `latitude`/`longitude` pairs). Nearest provider road
  fragment only, **not** direction/route matched, whole-area traffic, physical
  vehicle density or a trip ETA. The provider gives no observation timestamp
  here, so `valid_at=null`; never substitute retrieval time as observation time.

## Configuration and failures

Backend `.env` only:

```dotenv
OPENAQ_API_KEY=your_openaq_key
TOMTOM_API_KEY=your_tomtom_key
```

Get the OpenAQ v3 key from https://explore.openaq.org/ and enable a TomTom Traffic
API key in the provider account. Missing credentials yield `not_configured` for
that signal; other signals still load. Never place provider keys in Flutter.

Provider failures return reasons such as `provider_access_denied`,
`provider_rate_limited`, `provider_error`, `provider_unreachable`, or
`provider_timeout`; provider payloads and credential-bearing URLs are never
returned or logged. No retries, redirects, fabricated values or AQI provider
fallbacks are used. Request timeouts are four seconds, each signal has an
eight-second total deadline, and at most eight aggregate lookups run per process.
Overload returns the existing JSON 503 `unavailable` response. There is no
automatic polling in Flutter.

This initial slice does not persist/cache responses or collect training data.
Review provider storage, reuse, attribution and ML licensing before adding a
cache/archive. Add per-user rate limits and deployment-wide quota controls
before a public launch; the concurrency cap is not a request-rate limit.

## Evidence and limitations

Tests call the real authenticated Axum route and provider adapters against local
HTTP stand-ins, exercising normalization, weather fallback, missing credentials,
stale readings and sanitized failures. The stand-ins follow provider docs:

- https://open-meteo.com/en/docs
- https://data.bmkg.go.id/prakiraan-cuaca/
- https://docs.openaq.org/resources/locations
- https://docs.openaq.org/resources/latest
- https://developer.tomtom.com/traffic-api/documentation/tomtom-maps/v1/traffic-flow/flow-segment-data

Open-Meteo and BMKG public response shapes were inspected during development.
Live OpenAQ/TomTom account access and individual-road/station coverage remain
to be verified with your keys. This endpoint does not implement routing,
route-wide sampling, model training, Supra predictions, or automatic alerts.
