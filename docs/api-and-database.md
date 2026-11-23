# API & Database Reference

## 1. Backend REST API (`backend/src/routes.rs`)

### Public Endpoints
| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/health/live` | Liveness probe (`{"status":"ok"}`). Does not touch the database. |
| `GET` | `/health/ready` | Readiness probe checking SQLx PostgreSQL pool acquisition (`200 OK` or `503 Service Unavailable`). |
| `GET` | `/uploads/avatars/{filename}` | Serves uploaded user avatar PNG images from `AVATAR_STORAGE_DIR`. |

### Protected Endpoints (Require `Authorization: Bearer <supabase_jwt>`)
All `/api/*` endpoints authenticate against Supabase JWKS and derive caller identity from the verified `sub` claim.

#### Environmental Conditions, Forecasts & Mobility
| Method | Path | Handler | Description |
| --- | --- | --- | --- |
| `GET` | `/api/conditions/current` | `conditions::current` | Aggregated weather (Open-Meteo / optional BMKG `adm4`), air quality (OpenAQ / CAMS), and TomTom road flow for `latitude`, `longitude`. |
| `GET` | `/api/forecast/hourly` | `intelligence::forecast` | Proxies 12-hour PyTorch predictions (`ForecastNet`) from the loopback Python service for Greater Jakarta coordinates. |
| `POST` | `/api/mobility/plan` | `mobility::plan` | Plans routes (`car`, `motorcycle`, `walk`, `public_transit`) via OSRM, Valhalla, or Transjakarta GTFS + Commute Data API. |
| `POST` | `/api/agent/chat` | `agent::chat` | Agent 1 conversational assistant backed by Gemini (`GEMINI_API_KEY`) with server-fetched route/location evidence and deterministic summary fallback. |

#### Users & Profiles
| Method | Path | Handler | Description |
| --- | --- | --- | --- |
| `GET`, `PUT` | `/api/profile` | `users::get_profile`, `users::update_profile` | Reads or updates the authenticated user's profile. |
| `POST` | `/api/profile/avatar` | `users::upload_avatar` | Uploads, validates, resizes, and re-encodes an avatar image as PNG (`<= 5 MB`). |
| `DELETE` | `/api/account` | `users::delete_account` | Deletes the caller's application account records. |
| `POST`, `GET` | `/api/users` | `users::create_user`, `users::list_users` | Upserts profile on sign-in or returns only the caller's profile. |
| `GET`, `PUT`, `DELETE` | `/api/users/{id}` | `users::get_user`, `users::update_user`, `users::delete_user` | Account-owned CRUD (`require_self`). |

#### Saved Places, Routines, Trips & Routes
| Method | Path | Handler | Description |
| --- | --- | --- | --- |
| `GET`, `POST` | `/api/places` | `commutes::list_places`, `commutes::create_place` | Lists or creates saved places (`home`, `work`, `school`, `custom`) inside Jabodetabek. |
| `PUT`, `DELETE` | `/api/places/{id}` | `commutes::update_place`, `commutes::delete_place` | Full replacement or deletion of an owned saved place. |
| `GET`, `POST` | `/api/routines` | `commutes::list_routines`, `commutes::create_routine` | Lists or creates weekday commute routines (`Asia/Jakarta` departure minute & lead time). |
| `PUT`, `DELETE` | `/api/routines/{id}` | `commutes::update_routine`, `commutes::delete_routine` | Updates or deletes an owned routine. |
| `POST`, `GET` | `/api/trips` | `trips::create_trip`, `trips::list_trips` | Creates planned/confirmed trips (with coordinates, `transport_mode`, `route_waypoints`) or lists caller's trips. |
| `GET`, `PUT`, `DELETE` | `/api/trips/{id}` | `trips::get_trip`, `trips::update_trip`, `trips::delete_trip` | Owned trip CRUD. |
| `PUT`, `POST` | `/api/trips/{id}/finish` | `commutes::finish_trip` | Ends active current-trip alert monitoring while retaining trip history. |
| `GET` | `/api/users/{user_id}/trips` | `trips::get_user_trips` | Owned trip list for `user_id`. |
| `POST`, `GET`, `PUT`, `DELETE` | `/api/routes`, `/api/routes/{id}`, `/api/trips/{trip_id}/routes` | `route_handlers::*` | Owned route geometry & distance records attached to trips. |
| `GET` | `/api/predictions`, `/api/predictions/{id}`, `/api/routes/{route_id}/predictions` | `predictions::*` | Read-only access to stored route predictions. |

#### Notifications, Alerts & Preferences
| Method | Path | Handler | Description |
| --- | --- | --- | --- |
| `GET`, `PUT` | `/api/users/{user_id}/preferences` | `notification_preferences::*` | Reads/updates `alert_unhealthy_aqi`, `alert_heavy_rain`, `alert_severe_traffic`, `alert_relevant_news`, and `news_min_severity` (`low` \| `medium` \| `high` \| `critical`). |
| `POST` | `/api/alerts/evaluate` | `alerts::evaluate_user` | Queues asynchronous hazard & news evaluation for due routines/active trips (`202 Accepted`). |
| `GET` | `/api/notifications`, `/api/notifications/{id}`, `/api/users/{user_id}/notifications` | `notifications::*` | Reads user notifications; supports `?news_min_severity=...&limit=...`. |
| `PUT` | `/api/notifications/{id}/read`, `/api/notifications/{id}/unread`, `/api/notifications/unread` | `notifications::*` | Marks a single notification read/unread, or marks a bounded list of selected IDs unread. |
| `PUT`, `DELETE` | `/api/notifications/read` | `notifications::mark_all_read`, `notifications::delete_read_notifications` | Marks all visible alerts read (`PUT`), or soft-deletes read alerts via `deleted_at` while retaining `event_key` deduplication (`DELETE`). |

---

## 2. Database Schema & Migrations (`backend/migrations/`)

All migrations are applied via `supra_backend migrate` (`sqlx::migrate!`). Direct `anon` and `authenticated` Supabase roles have all table privileges revoked and Row-Level Security enabled; Axum connects with a server-only Postgres role.

### Applied Migrations
1. `20261101000000_initial_schema.sql` — Creates baseline tables: `users`, `trips`, `routes`, `predictions`, `historical_data`, `notification_preferences`, and `notifications`, plus indexes.
2. `20261101000001_supabase_auth.sql` — Drops `users.password_hash`, enables RLS on all core tables, and revokes `anon`/`authenticated` table grants.
3. `20261108000000_add_user_avatar_url.sql` — Adds `users.avatar_url`.
4. `20261108000001_trip_confirmation.sql` — Adds `start_latitude`, `start_longitude`, `destination_latitude`, `destination_longitude`, and `confirmed_at` to `trips` with all-or-nothing coordinate constraints.
5. `20261109000000_commute_features.sql` — Adds `saved_places` (`home`/`work`/`school`/`custom` within Jabodetabek bounds), `routine_trips` (scheduled weekdays, `departure_minute`, `lead_minutes`, `alerts_enabled`, `news_enabled`), `alert_decisions` audit log, `trips.transport_mode`/`active_until`/`route_waypoints`/`last_checked_at`, `notification_preferences.alert_relevant_news`, and `notifications.event_key` (unique deduplication index)/`source_url`/`context`.
6. `20261116000000_news_severity_preferences.sql` — Adds `notification_preferences.news_min_severity` (`low`, `medium`, `high`, `critical`, default `low`).
7. `20261116000001_notification_dismissals.sql` — Adds `notifications.deleted_at` (`TIMESTAMPTZ`) and `notifications_visible_read` partial index so dismissed alerts are hidden without breaking `event_key` deduplication.

---

## 3. Loopback Python Service Endpoints (`ml/serve.py`)

Bound exclusively to `127.0.0.1:8001` (not exposed externally):
- `GET /health/live` — Returns `{"status": "ok", "framework": "PyTorch"}`.
- `GET /v1/model` — Returns trained model metadata from `ml/artifacts/forecast.pt` (`model_card`).
- `GET /v1/forecast?latitude=...&longitude=...` — Runs CPU PyTorch inference (10-minute per-hour-bucket cache) returning 12 hourly predictions.
- `GET /v1/news` — Returns parsed & severity-classified ANTARA RSS commuter items (5-minute cache).
