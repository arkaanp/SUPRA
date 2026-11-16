# Public transport routing

`POST /api/mobility/plan` with authenticated origin, destination and
`"mode":"public_transit"` now works with:

1. Transjakarta GTFS files supplied in repository `file_gtfs/`.
2. Public Commute Data API at https://api.commute.shiorilabs.id.

## Configuration

No API key or separate OTP service is required. Optional server variables:

```dotenv
COMMUTE_API_URL=https://api.commute.shiorilabs.id
# TRANSJAKARTA_GTFS_DIR=/absolute/path/to/file_gtfs
# OTP_GRAPHQL_URL=  # optional legacy override; leave unset for the sources above
```

Default feed location resolves relative to the backend crate, independent of the
server working directory. Mount the feed and set an absolute path in deployment.
Feed parsing occurs once at startup; restart after replacing files. Missing or
invalid GTFS logs a warning and leaves API routing enabled. No data is seeded or
migrated. The user-supplied feed remains separate from the small test fixtures;
confirm its distribution terms before bundling it for others.

## Planner

The native GTFS planner reads agency timezone, stops, routes, trips, stop_times,
shapes, frequencies, calendar, optional calendar_dates and transfers. It checks
service date/day (including prior service day for times after 24:00), pickup and
alighting rules, ordered shape geometry, and service exceptions. Routes lacking
usable ordered times/shapes are excluded; the supplied feed currently loads
576 usable patterns. Up to three boardings are considered within six hours.

Access/egress is limited to 1.5 km; nearby transfer walks to 250 m plus explicit
feed transfers are supported. Walking time uses 4.5 km/h, plus applicable feed
minimums and a 120-second reboarding buffer. These are estimates, not a pedestrian
street router. Approximate walk links are explicitly labelled schematic.

Frequency trips with exact_times=0 use a conservative one-headway wait and are
labelled estimates. They are never presented as live bus departures. Fixed and
exact-frequency trips use their timetable. Fare calculation from the local GTFS
is currently unavailable rather than inferred from a flat rate.

For the API, cache the station directory for six hours and timetables for five
minutes (bounded in-memory cache). Examine up to four station-pair candidates concurrently, retaining nearby KRL
choices independently of bus-stop density (two KRL access choices when available). `/fares/{from}/{to}?at=...` supplies itinerary/available fare. Use
published leg times when available; otherwise match the same nonempty vehicle
number and line at both boarding and alighting stations via `/timetable`.
The boarding row's estimatedArrival can refer to the line terminus and is not
used as the intermediate destination arrival. Missing schedule/coordinate data
makes that candidate unavailable. Station requests have a three-second HTTP timeout; each candidate has its own
six-second deadline. Failed candidates do not discard completed alternatives.

Return distinct valid local and API alternatives ordered by arrival time; deduplicate
identical ride sequences. Retain the native Transjakarta option alongside KRL
choices even when the bus arrives later. These are alternative
itineraries, not a combined live road/rail optimization engine. API results may
include its own bus/rail transfers; local GTFS is used for additional bus coverage.
A failed API does not discard a usable local bus itinerary. Routes outside the
walking/service horizon return 404 rather than an invented journey.

## Response and UI

Existing `mode`, `source`, `duration_seconds`, `distance_km`, `waypoints`, `steps`
and `fetched_at` remain for the earliest-arriving option. `alternatives` holds the
remaining complete route objects (omitted when empty); it excludes the primary
option. Each option has independent geometry, timing, fare and legs. Optional `transit` contains departure_at, arrival_at,
fare_idr (nullable), attribution, and ordered legs. Each leg includes mode, line,
from/to stop names, times, distance_km, estimated and geometry_kind:

- gtfs_shape: supplied bus route shape vertices.
- schematic_station_sequence: ordered API station coordinates, not track geometry.
- schematic_walk_link: endpoint/transfer connection, not pedestrian navigation.

The map displays this connected itinerary and samples environmental data along
it. Separate Transjakarta/KRL cards show boarding and alighting stops, leg
instructions, WIB times, available fare and limitations. Selecting a card changes
the map and condition samples for that itinerary. Conditions use chosen endpoint
names and reverse-geocoded intermediate street/area names. If geocoding fails,
nearby area names and coordinates remain available.
Confirmed trip history continues through the existing user-owned trip API.
Schedules are not live vehicle locations or delay-adjusted arrival guarantees.

## Attribution and licenses

Commute Data / Shiori Labs: https://data.commute.shiorilabs.id/docs,
ODbL-1.0. Preserve attribution and the applicable share-alike terms for derived
data. This does not relicense the application code. The local feed is attributed
to Transjakarta, separately from Commute Data.

Primary contracts:
- https://api.commute.shiorilabs.id/openapi.json
- https://gtfs.org/documentation/schedule/reference/

## Three testing stages

1. Unit: small GTFS fixtures, calendars/exceptions, frequency vs timetable,
   after-midnight service, transfers, CSV quoting, frontend parsing/UI checks.
2. Integration: local HTTP fixture verifies API schedules match the same vehicle
   at both stations; optional supplied-feed smoke tests Blok M–Kota. Optional
   live API test verifies Gondangdia–Depok.
3. System: build/restart backend and Flutter, select Transit, inspect legs/map,
   confirm/save/reload a trip. A successful routing integration test alone is
   not a complete authenticated device/system pass.

```sh
cd backend
cargo test --locked
cargo test --locked transit::gtfs::tests::supplied -- --ignored --nocapture
cargo test --locked transit::tests::live_commute -- --ignored --nocapture
cargo test --locked transit::tests::live_monas_ui -- --ignored --nocapture
```

The last two commands call the public API; do not include it in an offline CI job.
Database-test runners now filter specifically to the DB test so they do not
accidentally run public-provider checks when using `--ignored`.
