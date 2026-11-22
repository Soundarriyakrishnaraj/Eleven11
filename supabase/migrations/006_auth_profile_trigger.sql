
-- Eleven11: Automatically create profiles after registration

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_full_name text;
    v_dob date;
    v_tz text;
    v_dob_text text;
BEGIN
    v_full_name := NULLIF(
        BTRIM(NEW.raw_user_meta_data ->> 'full_name'), ''
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
        date_of_birth,
        tz
    )
    VALUES (
        NEW.id,
        v_full_name,
        v_dob,
        v_tz
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

-- Recreate trigger safely
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- Prevent direct execution by client roles
REVOKE ALL ON FUNCTION public.handle_new_user()
FROM PUBLIC, anon, authenticated;
