-- OPTIONAL DEMO DATA ONLY. Never use these values as real forecasts.
-- Apply after migrations, to a local/disposable database, with:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -v demo_user_id=AUTH_UUID -v demo_email=AUTH_EMAIL -f seeds/demo.sql
-- demo_user_id and demo_email must belong to the same real Supabase Auth user.
-- Stable IDs make repeated application idempotent. Existing rows are not changed.
BEGIN;

INSERT INTO users (id, full_name, email)
VALUES (:'demo_user_id'::uuid, 'Demo Commuter', :'demo_email')
ON CONFLICT (id) DO NOTHING;

INSERT INTO trips (id, user_id, name, start_location, destination, planned_departure)
VALUES ('d0000000-0000-4000-8000-000000000002',
        :'demo_user_id'::uuid,
        'Morning Commute (demo)', 'Jakarta Kota', 'Sudirman Central',
        NOW() + INTERVAL '8 hours')
ON CONFLICT (id) DO NOTHING;

INSERT INTO routes (id, trip_id, waypoints, total_distance)
VALUES ('d0000000-0000-4000-8000-000000000003',
        'd0000000-0000-4000-8000-000000000002',
        '[{"lat": -6.13, "lng": 106.82}, {"lat": -6.22, "lng": 106.80}]'::jsonb,
        12.5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO predictions (id, route_id, target_time, predicted_aqi,
                         predicted_rainfall_prob, predicted_traffic_density)
VALUES ('d0000000-0000-4000-8000-000000000004',
        'd0000000-0000-4000-8000-000000000003',
        NOW() + INTERVAL '2 hours', 85, 0.30, 0.55)
ON CONFLICT (id) DO NOTHING;

INSERT INTO historical_data (id, location_point, recorded_at,
                             actual_aqi, actual_rainfall, actual_traffic)
VALUES ('d0000000-0000-4000-8000-000000000005',
        'DEMO Jakarta Central', NOW() - INTERVAL '1 hour', 82, 1.2, 0.50)
ON CONFLICT (id) DO NOTHING;

INSERT INTO notification_preferences (id, user_id)
VALUES ('d0000000-0000-4000-8000-000000000006',
        :'demo_user_id'::uuid)
ON CONFLICT (id) DO NOTHING;

INSERT INTO notifications (id, user_id, title, message_body, severity)
VALUES ('d0000000-0000-4000-8000-000000000007',
        :'demo_user_id'::uuid,
        'Demo alert', 'Illustrative data, not a live forecast.', 'medium')
ON CONFLICT (id) DO NOTHING;

COMMIT;
