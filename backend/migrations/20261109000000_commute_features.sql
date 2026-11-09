CREATE TABLE saved_places (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 label VARCHAR(120) NOT NULL CHECK (length(trim(label)) > 0),
 kind TEXT NOT NULL CHECK (kind IN ('home','work','school','custom')),
 latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -6.9 AND -5.8),
 longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN 106.3 AND 107.3),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE (user_id,id), UNIQUE(user_id,label)
);
CREATE UNIQUE INDEX saved_places_named_kind ON saved_places(user_id,kind) WHERE kind <> 'custom';
CREATE TABLE routine_trips (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 label VARCHAR(120) NOT NULL CHECK (length(trim(label)) > 0),
 origin_id UUID NOT NULL, destination_id UUID NOT NULL,
 mode TEXT NOT NULL CHECK (mode IN ('car','motorcycle','walk','public_transit')),
 weekdays SMALLINT[] NOT NULL CHECK (cardinality(weekdays) BETWEEN 1 AND 7 AND weekdays <@ ARRAY[0,1,2,3,4,5,6]::SMALLINT[]),
 departure_minute INTEGER NOT NULL CHECK (departure_minute BETWEEN 0 AND 1439),
 timezone TEXT NOT NULL DEFAULT 'Asia/Jakarta' CHECK (timezone = 'Asia/Jakarta'),
 lead_minutes INTEGER NOT NULL DEFAULT 30 CHECK (lead_minutes BETWEEN 5 AND 180),
 enabled BOOLEAN NOT NULL DEFAULT TRUE,
 alerts_enabled BOOLEAN NOT NULL DEFAULT TRUE,
 news_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 last_checked_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 FOREIGN KEY (user_id,origin_id) REFERENCES saved_places(user_id,id) ON DELETE CASCADE,
 FOREIGN KEY (user_id,destination_id) REFERENCES saved_places(user_id,id) ON DELETE CASCADE,
 CHECK (origin_id <> destination_id)
);
ALTER TABLE trips
 ADD COLUMN transport_mode TEXT NOT NULL DEFAULT 'car' CHECK (transport_mode IN ('car','motorcycle','walk','public_transit')),
 ADD COLUMN active_until TIMESTAMPTZ,
 ADD COLUMN route_waypoints JSONB NOT NULL DEFAULT '[]'::JSONB CHECK (jsonb_typeof(route_waypoints)='array'),
 ADD COLUMN last_checked_at TIMESTAMPTZ;
ALTER TABLE notification_preferences ADD COLUMN alert_relevant_news BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE notifications ADD COLUMN event_key TEXT,
 ADD COLUMN source_url TEXT,
 ADD COLUMN context JSONB NOT NULL DEFAULT '{}'::JSONB;
CREATE UNIQUE INDEX notifications_event_dedup ON notifications(user_id,event_key) WHERE event_key IS NOT NULL;
CREATE TABLE alert_decisions (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 target_key TEXT NOT NULL, checked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 outcome TEXT NOT NULL
);
CREATE INDEX alert_decisions_user_time ON alert_decisions(user_id,checked_at DESC);
ALTER TABLE saved_places ENABLE ROW LEVEL SECURITY;
ALTER TABLE routine_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_decisions ENABLE ROW LEVEL SECURITY;
DO $$ DECLARE r TEXT; t TEXT; BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN
   FOREACH t IN ARRAY ARRAY['saved_places','routine_trips','alert_decisions'] LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I',t,r);
   END LOOP;
  END IF;
 END LOOP;
END $$;
