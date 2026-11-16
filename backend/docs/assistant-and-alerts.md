# Grounded Gemini assistant and alert preferences

## Assistant selection and evidence

The app forwards the selected Trip route to the assistant whenever its option
changes. The context pill shows start, destination and mode. A confirmed active
trip can be restored after restarting the app; the backend loads it by owned
trip ID. Without a route, chat uses the selected Home location. Signing out or
changing account clears the previous selection and chat state.

`POST /api/agent/chat` remains authenticated. Example selection:

```json
{
  "message": "What should I prepare for this KRL journey?",
  "context": {
    "selected_route": {
      "origin": [-6.1754, 106.8272],
      "destination": [-6.365, 106.828],
      "origin_name": "Monas",
      "destination_name": "Universitas Indonesia",
      "mode": "public_transit",
      "waypoints": [[-6.1754, 106.8272], [-6.28, 106.83], [-6.365, 106.828]],
      "instructions": ["Selected KRL plan: Juanda to Universitas Indonesia"]
    }
  }
}
```

Alternatively send `context.point: [latitude,longitude]` for a location or
`context.trip_id` for an owned saved trip. Coordinates must be in the service
area, waypoints must connect the endpoints, and context is bounded to 32 points
and 12 short instructions. Optional route distance/duration and instructions are
**app-selected plan estimates**, not freshly verified traffic or vehicle data.
They never authorize access to another account's trip.

For each message the backend independently fetches current conditions at origin,
a point along the selected geometry, and destination (or the selected location).
It also requests the identified experimental PyTorch forecast and reads current
owned publisher reports matched by area, respecting preferences. Lookups run
concurrently with time budgets. Legacy client AQI/weather/temperature fields are
accepted for compatibility but are excluded from Gemini's environmental evidence.
Missing rainfall stays unavailable; raw instantaneous PM2.5 is not converted to
an AQI for the assistant. No fixed location overrides the selection.

Gemini receives structured evidence with provider source, signal kind/status,
valid time (including explicit WIB display fields), forecast model/input metadata, coverage limitations and selected
route. Route text, headlines, question/history and JSON values are data, never
system instructions. The prompt distinguishes current estimates/observations,
stale data, missing readings, future model predictions and schematic transit
connections. Point samples do not establish continuous coverage and nearest-road
traffic is not a route-wide average.

The response identifies `engine` (`gemini`, `server_data_summary` or
`scope_guardrail`), `model`, and `context_used`. An unavailable Gemini call yields
an explicitly labeled deterministic summary of actual server evidence. It never
impersonates Gemini. `MAX_TOKENS` partial replies are rejected. Gemini 2.5 Flash
uses a zero thinking budget and a separate output budget to avoid spending the
answer allowance before producing its response. Other model families do not
receive unsupported thinking settings. Client chat allows 35 seconds for the
combined provider/Gemini request while saves retain their existing timeout.

## Saved alert preferences

Apply the additive migration before restarting the updated backend:

```sh
cd backend
cargo run --locked -- migrate
```

`20261116000000_news_severity_preferences.sql` adds `news_min_severity` with a
constraint and default `low`. Existing alert flags remain. Account-scoped
`GET/PUT /api/users/{user_id}/preferences` supports:

- `alert_unhealthy_aqi`
- `alert_heavy_rain`
- `alert_severe_traffic`
- `alert_relevant_news`
- `news_min_severity`: `low`, `medium`, `high`, or `critical`

Updates are partial; omitted fields remain unchanged. Unknown severity values
return 400. Ownership applies to all reads and writes. Profile controls auto-save
and revert if a write fails. Alerts provides an entry point to the same
preferences and a severity selector that saves only the minimum field.

## News classification and filtering

The UI levels are All severities, Medium or higher, High or higher, and Critical
only. API `medium` is displayed as Medium. RSS severity is an explicit app rule
based on reported disruption terms in title/feed summary:

- Low: general announcements/information.
- Medium: reported disruption such as traffic diversions, service issues,
  inundation, power outage, reported collision/injuries or heavy rain.
- High: reported major disruption such as a road cut, total closure, collapsed
  bridge, flash flooding or suspended service.
- Critical: accepted from a configured reviewed incident feed; RSS rules do not
  infer this level.

This classification is not an official live warning or proof that an incident is
still occurring. Original publisher dates, article links, area precision and
expiry remain. News delivery checks both the news flag and saved minimum.
Existing articles can have their stored classification updated while retaining
read/sent state. Repeated unchanged checks remain deduplicated.

`GET /api/users/{user_id}/notifications?news_min_severity=high&limit=100` filters
news before pagination. Non-news weather/AQI/traffic alerts retain their own
preference logic and remain visible regardless of this news threshold. The
inbox selector immediately filters visible news, saves the account preference,
and reloads server results; failed saves restore the previous selection.

## Automated testing

1. Unit testing: `python3 testing/scripts/run_checks.py --stage unit` covers
   bounded inputs, route/evidence handling, view filtering, preferences, visible
   controls, selected unread and failed-save state.
2. Integration testing: `python3 testing/scripts/run_checks.py --stage integration`
   covers Gemini HTTP contracts, client errors and an isolated migrated database
   for owned routes, preference thresholds, inbox filtering, deduplication,
   read-state changes and deletion.

Optional running-service integration: `python3 testing/scripts/assistant_smoke.py`
uses the desktop session for read-only preference checks and one Gemini request
for public Monas–UI coordinates. It does not save trips or change preferences.
It is not included in the default local test run. See
[testing/README.md](../../testing/README.md).

Primary Gemini contracts: [generateContent](https://ai.google.dev/api/generate-content),
[thinking budget](https://ai.google.dev/gemini-api/docs/generate-content/thinking).

## Live preference updates and Delete read

Alerts listens to saved preference changes even while another tab is open.
Existing items and counts are filtered immediately; a background reload replaces
its data, and older in-flight replies cannot overwrite the new view. The saved
news minimum is also enforced on both server inbox-list endpoints. An explicit
lower `news_min_severity` query cannot bypass a stricter saved preference.
Known air/rain/traffic flags and the news switch apply to previously delivered
items as well as new delivery. Lowering a minimum or reenabling a type reloads
eligible existing items. Failed preference saves retain the previous setting.

Use the visible **Delete read alerts** button below the Alerts header. This removes all read
alerts for the signed-in account, including read items hidden by the current
view filter. Unread items are preserved. Repeating the action returns zero once
all read items are removed. Failures leave items available for retry.

The authenticated API is `DELETE /api/notifications/read`, returning
`{"deleted": N}`. Apply the additive migration
`20261116000001_notification_dismissals.sql` with `cargo run --locked -- migrate`.
Deletion records `deleted_at` and excludes these rows from list, detail, mark-read
and assistant-news reads. Event deduplication keys remain so a scheduled news
check or severity reclassification cannot recreate a removed alert. The action
does not change preferences or delete another account's notifications.

Unit/widget checks cover the exact Profile-tab change scenario, delayed reloads,
all flag types, read/unread deletion, repeated deletion and failure feedback.
The isolated DB test verifies preference floors, dismissal ownership and retained
event keys. `python3 testing/scripts/alerts_smoke.py` checks the live read paths
and unauthenticated deletion protection; it never deletes actual demo inbox data.

## Visible read-state controls

**Mark all read** and **Delete read alerts** are always in the visible toolbar,
with wrapping on narrow screens. Each row has **Mark read / Mark unread** and a
checkbox. Select one or more alerts, then use **Mark selected unread**. Selected
items are cleared after a successful batch and retained on failure for retry;
changing preferences prunes hidden selections.

Read-state API operations are authenticated and preserve sent times:

- `PUT /api/notifications/{id}/read` and `/unread`: one owned visible record.
- `PUT /api/notifications/read`: mark all currently preference-eligible unread
  alerts read in one request (including eligible pages beyond the client cache).
- `PUT /api/notifications/unread` with `{"ids":["uuid",...]}`: mark 1–100 distinct
  selected alerts unread atomically. A missing, deleted or foreign record rejects
  the whole selection. Repeating a valid selection is idempotent.

These operations reuse the existing read/dismissal columns; no further migration
is needed. Deleted records cannot be marked unread to restore them.

The service exposes immutable notification snapshots. The screen takes an owned
copy and uses replacement lists for state changes, fixing the previous
"Unsupported operation" error after a successful server deletion. Authenticated
client and widget regression tests exercise exactly that immutable-snapshot
path, including post-delete reload and repeat actions.

## Screenshot-based system testing

Current-trip alerts and profile controls are documented. Assistant relevance, routine visibility on Home/Alerts and routine-based alert evaluation remain open changes from the notes. See [the system-test record](../../testing/system/README.md) for source screenshots, outcomes and required retests.
