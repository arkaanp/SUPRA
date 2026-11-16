# Current conditions and route samples

Authenticated `GET /api/conditions/current?latitude=-6.2&longitude=106.82`
returns weather, air_quality and traffic with independent status, source, kind,
valid_at and data. Coordinates are bounded to Greater Jakarta. Optional `adm4`
must match the requested BMKG village; no automatic village lookup is provided.

## Weather freshness

Open-Meteo and BMKG (when an adm4 is supplied) are queried concurrently. Each
eligible response is compared by absolute distance of its valid time from now;
BMKG wins only when strictly closer. Open-Meteo wins ties. Weather estimates
older than two hours or implausibly future-dated are rejected. BMKG selects its
nearest three-hourly slot within -3/+6 hours and requires issuance within 24 hours.
BMKG remains labelled `provider_forecast`, including when the slot is in the past;
it is not a station observation. Missing BMKG rainfall is not filled from another
provider. Issued time and valid time are different; retrieval time is neither.

BMKG documents three-hourly forecasts, twice-daily updates, village adm4 codes,
a 60 requests/minute/IP limit and required attribution:
https://data.bmkg.go.id/prakiraan-cuaca/

## Air quality freshness and alternative

OpenAQ station metadata older than 24 hours is excluded before selecting up to
three candidates within 25 km. Known recently active stations take priority over
unknown-recency candidates, then distance orders candidates. Actual PM2.5 sensor
timestamps/units are checked; only readings within three hours count as current.
Station work has a three-second budget to leave time for the alternative.

If no fresh OpenAQ reading is usable, query Open-Meteo's CAMS global current
PM2.5 and provider-calculated US AQI. Response source is `open_meteo_cams`, kind
`model_estimate`. The model grid is approximately 45 km; similar values across
Jakarta are expected and do not imply street-level monitoring. Display CAMS,
Open-Meteo, CC BY 4.0 attribution and returned valid time. The API's AQI is used
directly; a single OpenAQ PM2.5 sample is not converted here into AQI.

CAMS values older than three hours or over 15 minutes in the future are rejected.
If CAMS fails, only a genuine OpenAQ reading at most 24 hours old can remain
stale. Otherwise air quality is unavailable. Cache retention also stops after
24 hours; refresh attempts do not advance the original data timestamp.

Official contracts:
- https://docs.openaq.org/resources/latest
- https://open-meteo.com/en/docs/air-quality-api

`OPENAQ_API_KEY` and `TOMTOM_API_KEY` remain backend-only. CAMS needs no key for
the public noncommercial endpoint; use an appropriate commercial plan for
commercial deployment. Provider quotas and attribution requirements still apply.

## Route map

Flutter samples the successful provider polyline by cumulative distance, including
start and destination, at a target of roughly 5 km with a maximum of five samples.
Lookups run at most two at a time and reuse the account/location repository cache.
Detailed sample cards appear below the transport options in the scrollable trip
sheet. They show air quality/PM2.5, weather, model/station identity and stale status;
expand source details for timestamps. Map squares use transparent AQI category
colors (or labelled PM2.5 concentration bands when AQI is absent), with blue rain
symbols and mm values. These squares are sample footprints, not measured areas. These are discrete samples, not a
continuous pollution heatmap or a route-wide exposure prediction. A point without
an adm4 uses Open-Meteo weather rather than borrowing another village's BMKG code.

TomTom remains nearest-road flow, not a trip ETA. Aggregate lookups have an
8-second per-signal deadline and an 8-request concurrency cap. Source failures
remain isolated. No automatic polling is introduced.

## Verification

Unit tests exercise closest-valid-time selection, CAMS fallback/stale rejection,
provider failure contracts, route endpoint/intermediate sampling, and rejection
of years-old cache data. `python3 testing/scripts/provider_freshness.py` inspects
live source timestamps without exposing keys. Live availability is reported
separately from deterministic fixture tests.
