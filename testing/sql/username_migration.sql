-- Only run by the test harness in its newly initialized database.
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY, email text, raw_user_meta_data jsonb);
BEGIN;
CREATE TABLE public.users (id uuid PRIMARY KEY, full_name text NOT NULL, email text NOT NULL);
INSERT INTO public.users VALUES
    ('10000000-0000-0000-0000-000000000001', 'Demo Rider', 'one@example.invalid'),
    ('10000000-0000-0000-0000-000000000002', 'DEMO RIDER', 'two@example.invalid'),
    ('10000000-0000-0000-0000-000000000003', '?', 'three@example.invalid');
\ir ../../backend/migrations/20261121000000_usernames.sql
DO $$
BEGIN
    IF (SELECT count(*) FROM public.users WHERE username IN ('demo_rider',
        'user_10000000000000000000000000000002', 'user_10000000000000000000000000000003')) <> 3 THEN
        RAISE EXCEPTION 'Legacy username backfill failed';
    END IF;
    INSERT INTO auth.users VALUES (gen_random_uuid(), 'signup@example.invalid', '{"username":"My_Handle"}');
    IF NOT EXISTS (SELECT FROM public.users WHERE username='my_handle' AND email='signup@example.invalid') THEN
        RAISE EXCEPTION 'Signup did not reserve a username';
    END IF;
    BEGIN
        INSERT INTO auth.users VALUES (gen_random_uuid(), 'duplicate@example.invalid', '{"username":"mY_hAndle"}');
        RAISE EXCEPTION 'Duplicate username accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    IF EXISTS (SELECT FROM auth.users WHERE email='duplicate@example.invalid') THEN
        RAISE EXCEPTION 'Duplicate handle left an Auth account behind';
    END IF;
END $$;
ROLLBACK;
