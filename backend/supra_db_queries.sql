-- ============================================================================
-- Supra Database System - PostgreSQL Schema & Queries
-- LEGACY REFERENCE ONLY: this file mixes schema and executable demo DML.
-- Use migrations/ for schema and seeds/ for explicit demo data instead.
-- Do not execute this whole file against a live database.
-- Reference: instructions/uml_diagrams.md (Section 2: Entity-Relationship Diagram)
-- System: Trip-Based Dynamic Air Quality and Weather Forecast with Agentic AI
-- Database: PostgreSQL (via Supabase)
--
-- NOTE ON PARAMETERS ($1, $2, ...):
--   Executable statements below use concrete literal values so they run
--   directly in the Supabase SQL Editor. For use in the Node.js backend,
--   replace literals with $1, $2, ... — commented templates are provided
--   next to each operation.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. EXTENSIONS
-- ----------------------------------------------------------------------------
-- gen_random_uuid() is provided by pgcrypto (built-in on Supabase).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. SCHEMA / DDL  (CREATE TABLE)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(255) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS 'App users (commuters, health-conscious users, delivery riders).';
COMMENT ON COLUMN users.password_hash IS 'Hashed password (bcrypt/argon2), never plaintext.';

CREATE TABLE IF NOT EXISTS trips (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name             VARCHAR(255) NOT NULL,
    start_location   VARCHAR(255) NOT NULL,
    destination      VARCHAR(255) NOT NULL,
    planned_departure TIMESTAMPTZ NOT NULL,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE trips IS 'A trip planned by a user; contains one or more routes.';
COMMENT ON COLUMN trips.planned_departure IS 'When the user plans to depart.';

CREATE TABLE IF NOT EXISTS routes (
    id               UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id          UUID      NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    waypoints        JSONB     NOT NULL DEFAULT '[]'::jsonb,
    total_distance   FLOAT     NOT NULL CHECK (total_distance >= 0),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE routes IS 'A route within a trip; waypoints stored as JSONB (lat/lng array).';
COMMENT ON COLUMN routes.waypoints IS 'Ordered list of waypoints, e.g. [{"lat":-6.2,"lng":106.8}, ...].';

CREATE TABLE IF NOT EXISTS predictions (
    id                   UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id             UUID      NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    target_time          TIMESTAMPTZ NOT NULL,
    predicted_aqi        FLOAT     NOT NULL CHECK (predicted_aqi >= 0),
    predicted_rainfall_prob FLOAT   NOT NULL CHECK (predicted_rainfall_prob BETWEEN 0 AND 1),
    predicted_traffic_density FLOAT NOT NULL CHECK (predicted_traffic_density BETWEEN 0 AND 1),
    generated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_route_target_time UNIQUE (route_id, target_time)
);

COMMENT ON TABLE predictions IS 'ML-generated 1-6 hour forecast cached per route (workflow 1 cache).';
COMMENT ON COLUMN predictions.target_time IS 'The future time the forecast applies to.';
COMMENT ON COLUMN predictions.generated_at IS 'When the ML engine produced this prediction (cache freshness).';

CREATE TABLE IF NOT EXISTS historical_data (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    location_point VARCHAR(255) NOT NULL,
    recorded_at    TIMESTAMPTZ NOT NULL,
    actual_aqi     FLOAT       NOT NULL CHECK (actual_aqi >= 0),
    actual_rainfall FLOAT      NOT NULL CHECK (actual_rainfall >= 0),
    actual_traffic FLOAT       NOT NULL CHECK (actual_traffic BETWEEN 0 AND 1)
);

COMMENT ON TABLE historical_data IS 'Observed ground-truth environmental data used for training & accuracy checks.';
COMMENT ON COLUMN historical_data.location_point IS 'Location identifier (e.g. "Jakarta-Central" or lat/lng string).';

CREATE TABLE IF NOT EXISTS notification_preferences (
    id                  UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID      NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    alert_unhealthy_aqi BOOLEAN   NOT NULL DEFAULT TRUE,
    alert_heavy_rain    BOOLEAN   NOT NULL DEFAULT TRUE,
    alert_severe_traffic BOOLEAN  NOT NULL DEFAULT TRUE,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE notification_preferences IS 'Per-user alert subscription flags (workflow 2).';

CREATE TABLE IF NOT EXISTS notifications (
    id           UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title        VARCHAR(255) NOT NULL,
    message_body TEXT      NOT NULL,
    severity     VARCHAR(20)  NOT NULL CHECK (severity IN ('low','medium','high','critical')),
    sent_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_read      BOOLEAN    NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE notifications IS 'Push/in-app notifications delivered to users (Agent 2 output).';

-- ----------------------------------------------------------------------------
-- 2. INDEXES  (support the query patterns in the sequence diagrams)
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_trips_user_id ON trips(user_id);
CREATE INDEX IF NOT EXISTS idx_trips_planned_departure ON trips(planned_departure);

CREATE INDEX IF NOT EXISTS idx_routes_trip_id ON routes(trip_id);

CREATE INDEX IF NOT EXISTS idx_predictions_route_id ON predictions(route_id);
CREATE INDEX IF NOT EXISTS idx_predictions_target_time ON predictions(target_time);
CREATE INDEX IF NOT EXISTS idx_predictions_generated_at ON predictions(generated_at);
CREATE INDEX IF NOT EXISTS idx_predictions_route_generated ON predictions(route_id, generated_at DESC);

CREATE INDEX IF NOT EXISTS idx_historical_location_recorded ON historical_data(location_point, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_notif_prefs_user_id ON notification_preferences(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON notifications(user_id, is_read) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_notifications_sent_at ON notifications(sent_at DESC);

-- ----------------------------------------------------------------------------
-- 3. DML QUERIES
-- ----------------------------------------------------------------------------
-- The statements below use concrete literal values so they run directly
-- in the Supabase SQL Editor. Replace literals with $1, $2, ... for backend use.

-- ============================================================================
-- 3A. USER MANAGEMENT
-- ============================================================================

-- Register a new user (auth signup).
-- BACKEND: INSERT INTO users (full_name, email, password_hash) VALUES ($1, $2, $3) RETURNING ...;
INSERT INTO users (full_name, email, password_hash)
VALUES ('Example User', 'user@example.com', '$2b$10$hashedplaceholder')
RETURNING id, full_name, email, created_at;

-- Authenticate: fetch user by email for password verification.
-- BACKEND: SELECT ... FROM users WHERE email = $1;
SELECT id, full_name, email, password_hash, created_at
FROM users
WHERE email = 'user@example.com';

-- Get user profile by ID.
-- BACKEND: SELECT ... FROM users WHERE id = $1;
SELECT id, full_name, email, created_at
FROM users
WHERE email = 'user@example.com';

-- Update user profile.
-- BACKEND: UPDATE users SET full_name = COALESCE($2, full_name), email = COALESCE($3, email) WHERE id = $1 RETURNING ...;
UPDATE users
SET full_name = 'Example User Updated',
    email     = 'user.updated@example.com'
WHERE email = 'user@example.com'
RETURNING id, full_name, email;

-- Delete user (cascades to trips, preferences, notifications).
-- BACKEND: DELETE FROM users WHERE id = $1;
-- DELETE FROM users WHERE email = 'user@example.com';

-- ============================================================================
-- 3B. TRIP MANAGEMENT
-- ============================================================================

-- Create a new trip (planned by a user).
-- BACKEND: INSERT INTO trips (user_id, name, start_location, destination, planned_departure) VALUES ($1,...$5) RETURNING ...;
INSERT INTO trips (user_id, name, start_location, destination, planned_departure)
VALUES ((SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1),
        'Example Trip', 'Start Location', 'Destination',
        NOW() + INTERVAL '8 hours')
RETURNING id, user_id, name, start_location, destination, planned_departure, created_at;

-- List a user's trips with route counts (trip history screen).
-- BACKEND: ... WHERE t.user_id = $1 ...
SELECT t.id, t.name, t.start_location, t.destination, t.planned_departure,
       COUNT(r.id) AS route_count
FROM trips t
LEFT JOIN routes r ON r.trip_id = t.id
WHERE t.user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1)
GROUP BY t.id, t.name, t.start_location, t.destination, t.planned_departure
ORDER BY t.planned_departure ASC;

-- Get a single trip with all its routes and latest prediction per route.
-- BACKEND: ... WHERE t.id = $1 AND t.user_id = $2;
SELECT t.id, t.name, t.start_location, t.destination, t.planned_departure,
       r.id AS route_id, r.waypoints, r.total_distance,
       p.id AS prediction_id, p.target_time, p.predicted_aqi,
       p.predicted_rainfall_prob, p.predicted_traffic_density, p.generated_at
FROM trips t
LEFT JOIN routes r ON r.trip_id = t.id
LEFT JOIN LATERAL (
    SELECT *
    FROM predictions p
    WHERE p.route_id = r.id
    ORDER BY p.target_time ASC
    LIMIT 1
) p ON TRUE
WHERE t.user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1)
ORDER BY t.planned_departure ASC;

-- Upcoming trips for a user (departure in the future).
-- BACKEND: ... WHERE user_id = $1 AND planned_departure > NOW() ...
SELECT id, name, start_location, destination, planned_departure
FROM trips
WHERE user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1)
  AND planned_departure > NOW()
ORDER BY planned_departure ASC;

-- Update trip details.
-- BACKEND: UPDATE trips SET name = COALESCE($2, name), ... WHERE id = $1 AND user_id = $2 RETURNING ...;
UPDATE trips
SET name = 'Example Trip (Updated)',
    planned_departure = NOW() + INTERVAL '9 hours'
WHERE id = (SELECT id FROM trips WHERE name = 'Example Trip' LIMIT 1)
  AND user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1)
RETURNING id, name, start_location, destination, planned_departure;

-- Delete a trip (cascades to routes and predictions).
-- BACKEND: DELETE FROM trips WHERE id = $1 AND user_id = $2;
-- DELETE FROM trips WHERE id = (SELECT id FROM trips WHERE name = 'Example Trip (Updated)' LIMIT 1);

-- ============================================================================
-- 3C. ROUTE MANAGEMENT
-- ============================================================================

-- Create a route for a trip (with waypoints as JSONB).
-- BACKEND: INSERT INTO routes (trip_id, waypoints, total_distance) VALUES ($1, $2::jsonb, $3) RETURNING ...;
INSERT INTO routes (trip_id, waypoints, total_distance)
VALUES ((SELECT id FROM trips WHERE name = 'Example Trip (Updated)' LIMIT 1),
        '[-6.13,106.82, -6.21,106.81, -6.22,106.80]'::jsonb,
        13.0)
RETURNING id, trip_id, waypoints, total_distance, created_at;

-- Get a route by ID with its waypoints.
-- BACKEND: SELECT ... FROM routes WHERE id = $1;
SELECT id, trip_id, waypoints, total_distance, created_at
FROM routes
WHERE id = (SELECT id FROM routes ORDER BY created_at DESC LIMIT 1);

-- Get all routes for a trip.
-- BACKEND: SELECT ... FROM routes WHERE trip_id = $1 ORDER BY created_at ASC;
SELECT id, waypoints, total_distance, created_at
FROM routes
WHERE trip_id = (SELECT id FROM trips WHERE name = 'Example Trip (Updated)' LIMIT 1)
ORDER BY created_at ASC;

-- Update route waypoints / distance.
-- BACKEND: UPDATE routes SET waypoints = COALESCE($2::jsonb, waypoints), total_distance = COALESCE($3, total_distance) WHERE id = $1 RETURNING ...;
UPDATE routes
SET total_distance = 13.5
WHERE id = (SELECT id FROM routes ORDER BY created_at DESC LIMIT 1)
RETURNING id, waypoints, total_distance;

-- Delete a route (cascades to predictions).
-- BACKEND: DELETE FROM routes WHERE id = $1;
-- DELETE FROM routes WHERE id = (SELECT id FROM routes ORDER BY created_at DESC LIMIT 1);

-- ============================================================================
-- 3D. PREDICTION QUERIES   (Workflow 1: Trip Forecast / Cache)
-- ============================================================================

-- Save ML-generated predictions to cache (route forecast, 1-6 hour outlook).
-- BACKEND: INSERT INTO predictions (route_id, target_time, predicted_aqi, predicted_rainfall_prob, predicted_traffic_density, generated_at) VALUES ($1,$2,$3,$4,$5,NOW()) ON CONFLICT ...;
INSERT INTO predictions (route_id, target_time, predicted_aqi,
                         predicted_rainfall_prob, predicted_traffic_density, generated_at)
VALUES ((SELECT id FROM routes ORDER BY created_at DESC LIMIT 1),
        NOW() + INTERVAL '3 hours',
        92.0, 0.45, 0.60, NOW())
ON CONFLICT (route_id, target_time) DO UPDATE
SET predicted_aqi = EXCLUDED.predicted_aqi,
    predicted_rainfall_prob = EXCLUDED.predicted_rainfall_prob,
    predicted_traffic_density = EXCLUDED.predicted_traffic_density,
    generated_at = NOW()
RETURNING id, route_id, target_time, predicted_aqi,
          predicted_rainfall_prob, predicted_traffic_density, generated_at;

-- Cache-hit check: recent cached predictions for a route within a target window.
-- Used by backend on GET /api/forecast/trip before calling external APIs / ML.
-- BACKEND: ... WHERE p.route_id = $1 AND p.generated_at >= NOW() - INTERVAL '1 hour' AND p.target_time BETWEEN $2 AND $3 ...
SELECT p.id, p.target_time, p.predicted_aqi, p.predicted_rainfall_prob,
       p.predicted_traffic_density, p.generated_at
FROM predictions p
WHERE p.route_id = (SELECT id FROM routes ORDER BY created_at DESC LIMIT 1)
  AND p.generated_at >= NOW() - INTERVAL '1 hour'
  AND p.target_time BETWEEN NOW() AND NOW() + INTERVAL '6 hours'
ORDER BY p.target_time ASC;

-- Latest prediction per target_time horizon for a route (most recent generation).
-- BACKEND: ... WHERE p.route_id = $1 ...
SELECT DISTINCT ON (p.target_time) p.id, p.target_time, p.predicted_aqi,
       p.predicted_rainfall_prob, p.predicted_traffic_density, p.generated_at
FROM predictions p
WHERE p.route_id = (SELECT id FROM routes ORDER BY created_at DESC LIMIT 1)
ORDER BY p.target_time ASC, p.generated_at DESC;

-- All predictions for a route ordered by target time (forecast series).
-- BACKEND: ... WHERE route_id = $1 ORDER BY target_time ASC;
SELECT id, target_time, predicted_aqi, predicted_rainfall_prob,
       predicted_traffic_density, generated_at
FROM predictions
WHERE route_id = (SELECT id FROM routes ORDER BY created_at DESC LIMIT 1)
ORDER BY target_time ASC;

-- Stale predictions older than 24 hours (cleanup candidate).
SELECT id, route_id, generated_at
FROM predictions
WHERE generated_at < NOW() - INTERVAL '24 hours';

-- Delete stale predictions.
-- DELETE FROM predictions WHERE generated_at < NOW() - INTERVAL '24 hours';

-- ============================================================================
-- 3E. HISTORICAL DATA QUERIES
-- ============================================================================

-- Store an observed (actual) environmental reading.
-- BACKEND: INSERT INTO historical_data (location_point, recorded_at, actual_aqi, actual_rainfall, actual_traffic) VALUES ($1,$2,$3,$4,$5) RETURNING ...;
INSERT INTO historical_data (location_point, recorded_at,
                             actual_aqi, actual_rainfall, actual_traffic)
VALUES ('Example Location', NOW() - INTERVAL '30 minutes',
        78.0, 2.5, 0.40)
RETURNING id, location_point, recorded_at, actual_aqi, actual_rainfall, actual_traffic;

-- Historical readings for a location within a time range.
-- BACKEND: ... WHERE location_point = $1 AND recorded_at BETWEEN $2 AND $3 ...
SELECT id, location_point, recorded_at, actual_aqi, actual_rainfall, actual_traffic
FROM historical_data
WHERE location_point = 'Example Location'
  AND recorded_at BETWEEN NOW() - INTERVAL '24 hours' AND NOW()
ORDER BY recorded_at DESC;

-- Latest reading per location (most recent observed values).
SELECT DISTINCT ON (location_point) location_point, recorded_at,
       actual_aqi, actual_rainfall, actual_traffic
FROM historical_data
ORDER BY location_point ASC, recorded_at DESC;

-- Prediction accuracy check: compare predicted vs actual for a route location.
SELECT p.target_time,
       p.predicted_aqi, h.actual_aqi,
       ROUND(ABS(p.predicted_aqi - h.actual_aqi)::numeric, 2) AS aqi_error,
       p.predicted_rainfall_prob, h.actual_rainfall,
       ROUND(ABS(p.predicted_rainfall_prob - h.actual_rainfall)::numeric, 2) AS rainfall_error,
       p.predicted_traffic_density, h.actual_traffic,
       ROUND(ABS(p.predicted_traffic_density - h.actual_traffic)::numeric, 2) AS traffic_error
FROM predictions p
JOIN routes r ON r.id = p.route_id
JOIN historical_data h
  ON h.location_point = 'Example Location'
 AND h.recorded_at BETWEEN p.target_time - INTERVAL '30 minutes'
                    AND p.target_time + INTERVAL '30 minutes'
WHERE p.route_id = (SELECT id FROM routes ORDER BY created_at DESC LIMIT 1);

-- ============================================================================
-- 3F. NOTIFICATION PREFERENCE QUERIES   (Workflow 2: Proactive Alerts)
-- ============================================================================

-- Create or update a user's notification preferences (upsert).
-- BACKEND: INSERT INTO notification_preferences (user_id, alert_unhealthy_aqi, alert_heavy_rain, alert_severe_traffic) VALUES ($1,$2,$3,$4) ON CONFLICT (user_id) DO UPDATE ...;
INSERT INTO notification_preferences (user_id,
                                      alert_unhealthy_aqi,
                                      alert_heavy_rain,
                                      alert_severe_traffic)
VALUES ((SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1),
        TRUE, TRUE, TRUE)
ON CONFLICT (user_id) DO UPDATE
SET alert_unhealthy_aqi = EXCLUDED.alert_unhealthy_aqi,
    alert_heavy_rain = EXCLUDED.alert_heavy_rain,
    alert_severe_traffic = EXCLUDED.alert_severe_traffic,
    updated_at = NOW()
RETURNING id, user_id, alert_unhealthy_aqi, alert_heavy_rain,
          alert_severe_traffic, updated_at;

-- Get a user's notification preferences.
-- BACKEND: SELECT ... FROM notification_preferences WHERE user_id = $1;
SELECT id, user_id, alert_unhealthy_aqi, alert_heavy_rain,
       alert_severe_traffic, updated_at
FROM notification_preferences
WHERE user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1);

-- ============================================================================
-- 3G. NOTIFICATION QUERIES
-- ============================================================================

-- Insert a generated notification (Agent 2 / LLM output delivered via FCM).
-- BACKEND: INSERT INTO notifications (user_id, title, message_body, severity, sent_at) VALUES ($1,$2,$3,$4,NOW()) RETURNING ...;
INSERT INTO notifications (user_id, title, message_body, severity, sent_at)
VALUES ((SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1),
        'Example Alert',
        'This is an example notification body.',
        'medium', NOW())
RETURNING id, user_id, title, message_body, severity, sent_at, is_read;

-- Get unread notifications for a user (newest first), with pagination.
-- BACKEND: ... WHERE user_id = $1 AND is_read = FALSE ORDER BY sent_at DESC LIMIT $2 OFFSET $3;
SELECT id, title, message_body, severity, sent_at, is_read
FROM notifications
WHERE user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1)
  AND is_read = FALSE
ORDER BY sent_at DESC
LIMIT 20 OFFSET 0;

-- Get all notifications for a user (newest first), with pagination.
-- BACKEND: ... WHERE user_id = $1 ORDER BY sent_at DESC LIMIT $2 OFFSET $3;
SELECT id, title, message_body, severity, sent_at, is_read
FROM notifications
WHERE user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1)
ORDER BY sent_at DESC
LIMIT 50 OFFSET 0;

-- Mark a single notification as read.
-- BACKEND: UPDATE notifications SET is_read = TRUE WHERE id = $1 AND user_id = $2 RETURNING ...;
UPDATE notifications
SET is_read = TRUE
WHERE id = (SELECT id FROM notifications WHERE is_read = FALSE ORDER BY sent_at ASC LIMIT 1)
  AND user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1)
RETURNING id, is_read;

-- Mark all notifications as read for a user.
-- BACKEND: UPDATE notifications SET is_read = TRUE WHERE user_id = $1 AND is_read = FALSE RETURNING id;
UPDATE notifications
SET is_read = TRUE
WHERE user_id = (SELECT id FROM users WHERE email = 'user.updated@example.com' LIMIT 1)
  AND is_read = FALSE
RETURNING id;

-- Delete old read notifications (retention cleanup).
DELETE FROM notifications
WHERE is_read = TRUE
  AND sent_at < NOW() - INTERVAL '30 days';

-- ============================================================================
-- 3H. PROACTIVE ALERT QUERY   (Workflow 2: Agent 2 Notification Engine)
-- ============================================================================

-- Query users in affected areas with matching preferences.
-- This is the DB step in the "Proactive AI Notifications" sequence diagram:
-- Cron -> DB: "Query users in affected areas with matching preferences"
-- Returns users whose routes have predictions crossing severity thresholds
-- AND who have enabled the corresponding alert preference,
-- excluding users already alerted recently (avoid spam).
-- BACKEND: same query (no parameters; uses NOW()).
SELECT DISTINCT u.id AS user_id,
       u.full_name,
       u.email,
       np.alert_unhealthy_aqi,
       np.alert_heavy_rain,
       np.alert_severe_traffic,
       p.target_time,
       p.predicted_aqi,
       p.predicted_rainfall_prob,
       p.predicted_traffic_density,
       CASE
         WHEN np.alert_unhealthy_aqi AND p.predicted_aqi >= 100 THEN 'high'
         WHEN np.alert_heavy_rain    AND p.predicted_rainfall_prob >= 0.7 THEN 'high'
         WHEN np.alert_severe_traffic AND p.predicted_traffic_density >= 0.8 THEN 'medium'
         ELSE 'low'
       END AS suggested_severity
FROM users u
JOIN notification_preferences np ON np.user_id = u.id
JOIN trips t ON t.user_id = u.id
JOIN routes r ON r.trip_id = t.id
JOIN predictions p ON p.route_id = r.id
WHERE p.target_time BETWEEN NOW() AND NOW() + INTERVAL '6 hours'
  AND (
        (np.alert_unhealthy_aqi   AND p.predicted_aqi >= 100)
     OR (np.alert_heavy_rain      AND p.predicted_rainfall_prob >= 0.7)
     OR (np.alert_severe_traffic  AND p.predicted_traffic_density >= 0.8)
  )
  AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.user_id = u.id
        AND n.sent_at >= NOW() - INTERVAL '3 hours'
  )
ORDER BY suggested_severity DESC, p.target_time ASC;

-- Count of affected users per alert type (for cron job sizing).
SELECT
       COUNT(*) FILTER (WHERE np.alert_unhealthy_aqi   AND p.predicted_aqi >= 100)   AS unhealthy_aqi_users,
       COUNT(*) FILTER (WHERE np.alert_heavy_rain      AND p.predicted_rainfall_prob >= 0.7) AS heavy_rain_users,
       COUNT(*) FILTER (WHERE np.alert_severe_traffic  AND p.predicted_traffic_density >= 0.8) AS severe_traffic_users
FROM users u
JOIN notification_preferences np ON np.user_id = u.id
JOIN trips t ON t.user_id = u.id
JOIN routes r ON r.trip_id = t.id
JOIN predictions p ON p.route_id = r.id
WHERE p.target_time BETWEEN NOW() AND NOW() + INTERVAL '6 hours';

-- ============================================================================
-- 3I. ANALYTICS / REPORTING QUERIES
-- ============================================================================

-- Average observed AQI by location over the last 24 hours.
SELECT location_point,
       ROUND(AVG(actual_aqi)::numeric, 2) AS avg_aqi,
       ROUND(AVG(actual_rainfall)::numeric, 2) AS avg_rainfall,
       ROUND(AVG(actual_traffic)::numeric, 2) AS avg_traffic,
       COUNT(*) AS reading_count
FROM historical_data
WHERE recorded_at >= NOW() - INTERVAL '24 hours'
GROUP BY location_point
ORDER BY avg_aqi DESC;

-- Trip count per user (most active planners).
SELECT u.id, u.full_name, u.email, COUNT(t.id) AS trip_count
FROM users u
LEFT JOIN trips t ON t.user_id = u.id
GROUP BY u.id, u.full_name, u.email
ORDER BY trip_count DESC
LIMIT 10;

-- Unread notification count per user.
SELECT user_id, COUNT(*) AS unread_count
FROM notifications
WHERE is_read = FALSE
GROUP BY user_id;

-- ============================================================================
-- END OF FILE
-- ============================================================================
