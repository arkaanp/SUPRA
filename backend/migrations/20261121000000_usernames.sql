-- Profile ownership stays with the original Auth UUID. Give colliding or
-- unusable legacy names distinct handles in a reserved namespace.
ALTER TABLE public.users RENAME COLUMN full_name TO username;
WITH candidates AS (
    SELECT id, left(trim(both '_' from regexp_replace(lower(username COLLATE "C"),
        '[^a-z0-9_]+', '_', 'g')), 32) AS handle FROM public.users
), ranked AS (
    SELECT *, row_number() OVER (PARTITION BY handle ORDER BY id) AS position FROM candidates
)
UPDATE public.users u SET username = CASE
    WHEN length(r.handle) >= 3 AND r.position = 1 THEN r.handle
    ELSE 'user_' || replace(u.id::text, '-', '') END
FROM ranked r WHERE u.id = r.id;

ALTER TABLE public.users ADD CONSTRAINT users_username_format CHECK (
    username COLLATE "C" ~ '^[a-z0-9_]{3,32}$'
    OR username = 'user_' || replace(id::text, '-', '')
);
ALTER TABLE public.users ADD CONSTRAINT users_username_key UNIQUE (username);

-- Reserve a requested handle in the same transaction as email signup, even
-- when Supabase requires confirmation before issuing its first session.
CREATE FUNCTION public.supra_signup_profile() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    INSERT INTO public.users (id, email, username)
    VALUES (NEW.id, NEW.email, lower(btrim(NEW.raw_user_meta_data->>'username') COLLATE "C"));
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.supra_signup_profile() FROM PUBLIC;
DO $$
BEGIN
    IF to_regclass('auth.users') IS NOT NULL THEN
        CREATE TRIGGER supra_signup_profile AFTER INSERT ON auth.users
            FOR EACH ROW WHEN (NEW.email IS NOT NULL AND NEW.raw_user_meta_data ? 'username')
            EXECUTE FUNCTION public.supra_signup_profile();
    END IF;
END $$;
