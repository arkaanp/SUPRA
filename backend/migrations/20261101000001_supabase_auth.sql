-- Profile IDs now come from a verified Supabase access token (sub).
-- Back up and review existing app-only users first: their UUIDs are not Auth
-- identities. Migrate ownership explicitly; never match accounts by email.
ALTER TABLE public.users DROP COLUMN IF EXISTS password_hash;
ALTER TABLE public.users ALTER COLUMN id DROP DEFAULT;
COMMENT ON COLUMN public.users.id IS 'Supabase Auth subject UUID; Supabase owns credentials.';

-- The mobile client uses Auth only. Axum accesses these tables using a server-
-- only database connection that bypasses RLS; it must enforce user ownership.
-- No direct table policies are installed for anon/authenticated.
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historical_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- These roles exist on Supabase, but not on a plain PostgreSQL test database.
DO $$
DECLARE
    api_role text;
    table_name text;
BEGIN
    FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = api_role) THEN
            FOREACH table_name IN ARRAY ARRAY['users', 'trips', 'routes', 'predictions',
                'historical_data', 'notification_preferences', 'notifications',
                'conversations', 'messages'] LOOP
                IF to_regclass(format('public.%I', table_name)) IS NOT NULL THEN
                    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I', table_name, api_role);
                END IF;
            END LOOP;
        END IF;
    END LOOP;
END $$;
