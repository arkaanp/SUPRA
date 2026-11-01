-- Baseline schema. Safe to apply to a database with these same tables already
-- present; verify existing table/column definitions before adopting it there.
-- Never run the example DML in supra_db_queries.sql as a migration.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS 'App users (commuters, health-conscious users, delivery riders).';
COMMENT ON COLUMN users.password_hash IS 'Hashed password (bcrypt/argon2), never plaintext.';

CREATE TABLE IF NOT EXISTS trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    start_location VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    planned_departure TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE trips IS 'A trip planned by a user; contains one or more routes.';
COMMENT ON COLUMN trips.planned_departure IS 'When the user plans to depart.';

CREATE TABLE IF NOT EXISTS routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    waypoints JSONB NOT NULL DEFAULT '[]'::jsonb,
    total_distance FLOAT NOT NULL CHECK (total_distance >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE routes IS 'A route within a trip; waypoints stored as JSONB (lat/lng array).';
COMMENT ON COLUMN routes.waypoints IS 'Ordered list of waypoints, e.g. [{"lat":-6.2,"lng":106.8}, ...].';

CREATE TABLE IF NOT EXISTS predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    target_time TIMESTAMPTZ NOT NULL,
    predicted_aqi FLOAT NOT NULL CHECK (predicted_aqi >= 0),
    predicted_rainfall_prob FLOAT NOT NULL CHECK (predicted_rainfall_prob BETWEEN 0 AND 1),
    predicted_traffic_density FLOAT NOT NULL CHECK (predicted_traffic_density BETWEEN 0 AND 1),
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_route_target_time UNIQUE (route_id, target_time)
);

COMMENT ON TABLE predictions IS 'ML-generated 1-6 hour forecast cached per route (workflow 1 cache).';
COMMENT ON COLUMN predictions.target_time IS 'The future time the forecast applies to.';
COMMENT ON COLUMN predictions.generated_at IS 'When the ML engine produced this prediction (cache freshness).';

CREATE TABLE IF NOT EXISTS historical_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_point VARCHAR(255) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    actual_aqi FLOAT NOT NULL CHECK (actual_aqi >= 0),
    actual_rainfall FLOAT NOT NULL CHECK (actual_rainfall >= 0),
    actual_traffic FLOAT NOT NULL CHECK (actual_traffic BETWEEN 0 AND 1)
);

COMMENT ON TABLE historical_data IS 'Observed ground-truth environmental data used for training & accuracy checks.';
COMMENT ON COLUMN historical_data.location_point IS 'Location identifier (e.g. "Jakarta-Central" or lat/lng string).';

CREATE TABLE IF NOT EXISTS notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    alert_unhealthy_aqi BOOLEAN NOT NULL DEFAULT TRUE,
    alert_heavy_rain BOOLEAN NOT NULL DEFAULT TRUE,
    alert_severe_traffic BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE notification_preferences IS 'Per-user alert subscription flags (workflow 2).';

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message_body TEXT NOT NULL,
    severity VARCHAR(20) NOT NULL CHECK (severity IN ('low','medium','high','critical')),
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_read BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE notifications IS 'Push/in-app notifications delivered to users (Agent 2 output).';

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
