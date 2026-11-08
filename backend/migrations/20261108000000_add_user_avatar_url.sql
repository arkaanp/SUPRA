ALTER TABLE public.users ADD COLUMN IF NOT EXISTS avatar_url TEXT;
COMMENT ON COLUMN public.users.avatar_url IS 'Optional URL to user profile avatar image.';
