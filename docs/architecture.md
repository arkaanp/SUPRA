# Architecture & Subsystems

SUPRA is organized as a monorepo with four runtime layers: a **Flutter mobile/web/desktop client**, a **Rust/Axum API server**, a **Python PyTorch + RSS intelligence service**, and a **PostgreSQL + Auth layer managed by Supabase**.

---

## 1. Flutter Client (`mobile/`)

The Flutter application is pinned with FVM and enters via `main.dart` → [`app.dart`](../mobile/lib/app.dart) (`SupraApp`). When signed out, users route through `LoginScreen`, `RegisterScreen`, and `PasswordRecoveryScreen` (supporting 6-digit OTP codes and `io.supabase.supra://login-callback` deep links). Once authenticated, [`SupraShell`](../mobile/lib/screens/supra_shell.dart) hosts an `IndexedStack` with five tabs:

| Tab | Screen | Responsibility |
| --- | --- | --- |
| **Home** | `home_screen.dart` | Interactive Greater Jakarta location selector (with `adm4` BMKG mapping), teal Today's Air Quality card with `(?)` explainability guides, 12-hour ML/weather forecast strip, and synchronized recent trips. |
| **Trip** | `trip_screen.dart` | Map-based origin/destination selection, Car / Motorcycle / Walking / Public Transit routing (`RoutePlannerView`, `TransitJourneyDetails`), discrete route environmental sampling (`RouteEnvironmentSamples`), confirmation & live tracking, and persistent `TripHistoryStore`. |
| **Assistant** | `chat_screen.dart` | Conversational UI for **Agent 1**, forwarding active Trip selection or Home location to `/api/agent/chat` and displaying `ChatBubble` responses with `engine`/`model` attribution. |
| **Alerts** | `notifications_screen.dart` | In-app inbox for **Agent 2** hazard alerts & ANTARA commuter news, featuring news severity filtering (`NewsSeveritySelector`), manual evaluation trigger, bulk/individual read/unread selection, and read dismissal. |
| **Profile** | `settings_screen.dart` | Account profile & avatar upload, saved places (`Home`, `Work`, `School`, `Custom`) & daily routines (`commutes_screen.dart`), alert flags & `news_min_severity`, sign out, and account deletion. |

### Key Client Services (`mobile/lib/services/`)
- **Auth & API Transport:** `supra_api_service.dart`, `authenticated_client.dart`, `auth_http_client.dart`, `backend_api.dart` attach current Supabase JWTs, enforce origin checks, and clear account state on sign-out or user switch.
- **Caching & Repositories:** `conditions_repository.dart` and `forecast_repository.dart` persist account-scoped readings across restarts while retaining explicit **STALE** indicators and refusing years-old cache entries (`> 24h`).
- **Maps & Mobility:** `geographic_tile_map.dart`, `geocoding_service.dart`, `routing_service.dart`, `transit_network.dart`, and `commute_recommendations.dart` handle raster tile rendering, throttled Nominatim geocoding, multimodal routing, and exposure-weighted itinerary scoring.

---

## 2. Rust / Axum Backend (`backend/`)

The Axum server (`backend/src/main.rs`) binds `0.0.0.0:$PORT` (via `resolve_port`, defaulting to `3000`), validates Supabase JWTs on every `/api/*` route, and coordinates external providers.

### Modules (`backend/src/`)
| Module | Responsibility |
| --- | --- |
| `auth.rs` | Verifies Supabase ES256/RS256 access tokens via JWKS (4s timeout budget) and injects verified `AuthUser`; `require_self` blocks path-ID impersonation. |
| `routes.rs` & `handlers/` | Defines public (`/health/live`, `/health/ready`, `/uploads/avatars/{filename}`) and JWT-protected `/api/*` endpoints across `users`, `trips`, `routes`, `predictions`, `notifications`, `notification_preferences`, and `agent`. |
| `conditions.rs` | Queries Open-Meteo, optional BMKG (`adm4`), OpenAQ v3 (`<= 25 km`, active stations first, `<= 3h`), Open-Meteo CAMS (`45 km` fallback), and TomTom road flow concurrently with an 8-permit semaphore and 8s signal timeout. |
| `mobility.rs` | Orchestrates `/api/mobility/plan` across driving, motorcycle/walking (`VALHALLA_ROUTE_URL`), and `public_transit`. |
| `transit.rs` & `transit/gtfs.rs` | Combines local Transjakarta GTFS (`file_gtfs/`, 576 usable route patterns, up to 3 boardings within 6 hours) with Shiori Labs Commute Data API (`COMMUTE_API_URL`) for KRL/bus options, deduplicating identical itineraries without inventing fares or live arrivals. |
| `commutes.rs` | Manages user-owned `saved_places`, `routine_trips` (`Asia/Jakarta` schedules), and `finish_trip` active-monitoring termination. |
| `alerts.rs` | Runs **Agent 2** — an opt-in background worker (`ALERTS_ENABLED=true`, 1-minute cadence, 5-minute per-target cooldown) and `POST /api/alerts/evaluate` checking due routines/confirmed trips against fresh hazard conditions and filtered ANTARA news with event-key deduplication. |
| `intelligence.rs` | Bridges `/api/forecast/hourly` and news fetching to the loopback Python ML/RSS service (`INTELLIGENCE_URL`, default `http://127.0.0.1:8001`). |
| `handlers/agent.rs` | Powers **Agent 1** (`POST /api/agent/chat`) by verifying user-owned trip/route context, independently fetching live server conditions + ML forecasts + owned news, calling Google AI Studio Gemini (`GEMINI_API_KEY`, `GEMINI_MODEL`), and falling back transparently to `server_data_summary` if Gemini is unavailable. |
| `validation.rs`, `error.rs`, `models.rs`, `db.rs` | Enforces Jabodetabek coordinate bounds (`-6.9..-5.8` lat, `106.3..107.3` lon), strict JSON error codes (`400`/`401`/`404`/`405`/`503`), SQLx PgPool management, and `sqlx::migrate!` execution. |

---

## 3. Python ML & News Intelligence (`ml/`)

The Python service (`ml/serve.py`) runs on `127.0.0.1:8001` (loopback-only, capped at 4 concurrent permits, bounded in-memory TTL caches) to isolate PyTorch inference and RSS parsing from the Rust async runtime:

- **12-Hour Multi-Horizon Forecaster (`ml/model.py`, `ml/data.py`, `ml/train.py`, `ml/inference.py`):**
  - Architecture: `ForecastNet` MLP (`103 → 96 → 48 → 5` with `SiLU` activations) predicting 12 hourly horizons for residual temperature (`°C`), log precipitation (`mm`), PM2.5 (`µg/m³`), US AQI, and a wet-hour probability logit (`>= 0.1 mm/h`).
  - Inputs (`INPUT_SIZE = 103`): `24` consecutive historical hours of `[temp, precip, pm25, aqi]` plus `7` spatiotemporal/horizon features (WIB hour sin/cos, weekday sin/cos, normalized lat/lon, normalized horizon).
  - Data & Validation: Trained on 60 days of Open-Meteo & CAMS history across Jakarta, Depok, Bogor, Bekasi, and Tangerang with chronological 14-day holdout splits (7 validation, 7 test) so windows never leak across cutoffs. Rejects stale inputs (`> 2h`), missing hours, or checkpoints older than 90 days. Traffic forecasts remain explicitly `unavailable`.
- **Commuter News Parser (`ml/news.py`):**
  - Polls ANTARA Metro, Current News, Metro Lintas Kota, and ANTARA Megapolitan RSS feeds.
  - Rejects XML `<!DOCTYPE>` entity payloads, untrusted domains, stale/future items, non-Jabodetabek locations, and negated disruption headlines (e.g., *"Tidak ada banjir"*).
  - Classifies severity (`low`, `medium`, `high`) using explicit disruption rules (`critical` is reserved for `NEWS_INCIDENTS_URL` operator-reviewed feeds).

---

## 4. Data Scope & Coordinate Boundaries

- **Geographic Envelope:** Greater Jakarta / Jabodetabek (`latitude: -6.9` to `-5.8`, `longitude: 106.3` to `107.3`).
- **Database Security:** Supabase Auth holds credentials; Axum connects via a server-only Postgres role (`DATABASE_URL`) that bypasses RLS while enforcing `WHERE user_id = $1` from the verified JWT subject across every query.
