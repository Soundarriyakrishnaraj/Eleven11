-- Username authentication additions. Existing account rows remain untouched.
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS username text;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint
        WHERE conname = 'profiles_username_format'
          AND conrelid = 'public.profiles'::regclass
    ) THEN
        ALTER TABLE public.profiles
        ADD CONSTRAINT profiles_username_format
        CHECK (
            username IS NULL
            OR username ~ '^[A-Za-z0-9_]{3,30}$'
        ) NOT VALID;
    END IF;
END;
$$;

ALTER TABLE public.profiles
VALIDATE CONSTRAINT profiles_username_format;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_unique
ON public.profiles (lower(btrim(username)))
WHERE username IS NOT NULL;

-- Keep the existing idempotent profile trigger and extend its signup metadata.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_full_name text;
    v_username text;
    v_dob date;
    v_tz text;
    v_dob_text text;
BEGIN
    v_username := NULLIF(
        BTRIM(NEW.raw_user_meta_data ->> 'username'), ''
    );

    IF v_username IS NOT NULL
       AND v_username !~ '^[A-Za-z0-9_]{3,30}$' THEN
        RAISE EXCEPTION 'Invalid username';
    END IF;

    v_full_name := COALESCE(
        NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'full_name'), ''),
        v_username
    );
    v_dob_text := NULLIF(
        BTRIM(NEW.raw_user_meta_data ->> 'date_of_birth'), ''
    );
    v_tz := COALESCE(
        NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'tz'), ''),
        'UTC'
    );

    IF v_dob_text IS NOT NULL THEN
        BEGIN
            v_dob := v_dob_text::date;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid date of birth';
        END;
    END IF;

    INSERT INTO public.profiles (
        id,
        full_name,
        username,
        date_of_birth,
        tz
    )
    VALUES (
        NEW.id,
        v_full_name,
        v_username,
        v_dob,
        v_tz
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user()
FROM PUBLIC, anon, authenticated;

-- These privileged lookups are only for trusted Edge Functions.
CREATE OR REPLACE FUNCTION public.auth_lookup_email_for_username(
    p_username text
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
    SELECT u.email
    FROM public.profiles AS p
    JOIN auth.users AS u ON u.id = p.id
    WHERE p.username IS NOT NULL
      AND lower(btrim(p.username)) = lower(btrim(p_username))
      AND u.email IS NOT NULL
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.auth_registration_availability(
    p_username text,
    p_email text
)
RETURNS TABLE(username_exists boolean, email_exists boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
    SELECT
        EXISTS (
            SELECT 1
            FROM public.profiles AS p
            WHERE p.username IS NOT NULL
              AND lower(btrim(p.username)) = lower(btrim(p_username))
        ),
        EXISTS (
            SELECT 1
            FROM auth.users AS u
            WHERE u.email IS NOT NULL
              AND lower(btrim(u.email)) = lower(btrim(p_email))
        );
$$;

CREATE OR REPLACE FUNCTION public.auth_recovery_identity(
    p_username text,
    p_email text,
    p_date_of_birth date
)
RETURNS TABLE(user_id uuid, email text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
    SELECT u.id, u.email
    FROM public.profiles AS p
    JOIN auth.users AS u ON u.id = p.id
    WHERE p.username IS NOT NULL
      AND p.date_of_birth IS NOT NULL
      AND u.email IS NOT NULL
      AND lower(btrim(p.username)) = lower(btrim(p_username))
      AND lower(btrim(u.email)) = lower(btrim(p_email))
      AND p.date_of_birth = p_date_of_birth
    LIMIT 1;
$$;

CREATE TABLE IF NOT EXISTS public.auth_rate_limits (
    scope text NOT NULL,
    key_hash text NOT NULL,
    window_started_at timestamptz NOT NULL DEFAULT now(),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    PRIMARY KEY (scope, key_hash)
);

CREATE INDEX IF NOT EXISTS auth_rate_limits_window_idx
ON public.auth_rate_limits(window_started_at);

ALTER TABLE public.auth_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.auth_rate_limits FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.auth_rate_limits TO service_role;

CREATE OR REPLACE FUNCTION public.consume_auth_rate_limit(
    p_scope text,
    p_key_hash text,
    p_limit integer,
    p_window_seconds integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_attempts integer;
BEGIN
    IF p_scope IS NULL OR length(p_scope) > 40
       OR p_key_hash !~ '^[0-9a-f]{64}$'
       OR p_limit < 1 OR p_limit > 1000
       OR p_window_seconds < 1 OR p_window_seconds > 86400 THEN
        RAISE EXCEPTION 'Invalid rate limit parameters';
    END IF;

    DELETE FROM public.auth_rate_limits
    WHERE window_started_at < now() - interval '1 day';

    INSERT INTO public.auth_rate_limits (
        scope, key_hash, window_started_at, attempts
    )
    VALUES (p_scope, p_key_hash, now(), 1)
    ON CONFLICT (scope, key_hash) DO UPDATE
    SET
        window_started_at = CASE
            WHEN public.auth_rate_limits.window_started_at
                 <= now() - make_interval(secs => p_window_seconds)
            THEN now()
            ELSE public.auth_rate_limits.window_started_at
        END,
        attempts = CASE
            WHEN public.auth_rate_limits.window_started_at
                 <= now() - make_interval(secs => p_window_seconds)
            THEN 1
            ELSE public.auth_rate_limits.attempts + 1
        END
    RETURNING attempts INTO v_attempts;

    RETURN v_attempts <= p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.auth_lookup_email_for_username(text)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auth_registration_availability(text, text)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auth_recovery_identity(text, text, date)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.consume_auth_rate_limit(text, text, integer, integer)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.auth_lookup_email_for_username(text)
TO service_role;
GRANT EXECUTE ON FUNCTION public.auth_registration_availability(text, text)
TO service_role;
GRANT EXECUTE ON FUNCTION public.auth_recovery_identity(text, text, date)
TO service_role;
GRANT EXECUTE ON FUNCTION public.consume_auth_rate_limit(text, text, integer, integer)
TO service_role;
