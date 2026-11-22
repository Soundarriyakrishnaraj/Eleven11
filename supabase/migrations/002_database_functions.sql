
-- Eleven11: Secure database functions

-- 1. Update timestamps automatically.
CREATE OR REPLACE FUNCTION public.trigger_set_timestamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- 2. Validate date of birth.
CREATE OR REPLACE FUNCTION public.validate_profile_dob()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
    IF NEW.date_of_birth IS NOT NULL
       AND NEW.date_of_birth > CURRENT_DATE THEN
        RAISE EXCEPTION 'Date of birth cannot be in the future';
    END IF;
    RETURN NEW;
END;
$$;

-- 3. Check current user's admin role.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.admin_roles
        WHERE user_id = auth.uid()
    );
$$;

-- 4. Check ownership.
CREATE OR REPLACE FUNCTION public.is_owner(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, auth
AS $$
    SELECT p_user IS NOT NULL AND p_user = auth.uid();
$$;

-- 5. Validate goal category ownership.
CREATE OR REPLACE FUNCTION public.enforce_goal_category_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_category_user uuid;
BEGIN
    IF NEW.category_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT user_id INTO v_category_user
    FROM public.goal_categories
    WHERE id = NEW.category_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Goal category does not exist';
    END IF;

    IF v_category_user IS NOT NULL
       AND v_category_user <> NEW.user_id THEN
        RAISE EXCEPTION 'Goal category belongs to another user';
    END IF;

    RETURN NEW;
END;
$$;

-- 6. Enforce task ownership.
CREATE OR REPLACE FUNCTION public.enforce_task_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_goal_user uuid;
BEGIN
    IF NEW.goal_id IS NOT NULL THEN
        SELECT user_id INTO v_goal_user
        FROM public.goals
        WHERE id = NEW.goal_id
        FOR KEY SHARE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Goal does not exist';
        END IF;

        IF NEW.user_id IS NOT NULL
           AND NEW.user_id <> v_goal_user THEN
            RAISE EXCEPTION 'Task owner must match goal owner';
        END IF;

        NEW.user_id := v_goal_user;
    ELSIF NEW.user_id IS NULL THEN
        RAISE EXCEPTION 'Standalone tasks require an owner';
    END IF;

    RETURN NEW;
END;
$$;

-- 7. Enforce a maximum of five custom themes per user.
CREATE OR REPLACE FUNCTION public.enforce_custom_theme_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_count integer;
BEGIN
    PERFORM 1
    FROM public.profiles
    WHERE id = NEW.user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Theme owner profile does not exist';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.custom_themes
    WHERE user_id = NEW.user_id
      AND (TG_OP <> 'UPDATE' OR id <> NEW.id);

    IF v_count >= 5 THEN
        RAISE EXCEPTION 'Maximum of five custom themes allowed';
    END IF;

    RETURN NEW;
END;
$$;

-- 8. Secure daily quote interaction.
-- Repeated same-type interactions for the same quote/day return the
-- existing record instead of creating duplicate records.
CREATE OR REPLACE FUNCTION public.insert_quote_interaction(
    p_quote uuid,
    p_type text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
    v_user uuid;
    v_tz text;
    v_date date;
    v_id uuid;
BEGIN
    v_user := auth.uid();

    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_type IS NULL OR p_type NOT IN ('like', 'share', 'comment') THEN
        RAISE EXCEPTION 'Invalid interaction type';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.quotes
        WHERE id = p_quote AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Quote not found or inactive';
    END IF;

    SELECT tz INTO v_tz
    FROM public.profiles
    WHERE id = v_user;

    IF v_tz IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_timezone_names
        WHERE name = v_tz
    ) THEN
        v_tz := 'UTC';
    END IF;

    v_date := (now() AT TIME ZONE v_tz)::date;

    INSERT INTO public.quote_interactions (
        user_id, quote_id, interaction_type, interaction_date
    )
    VALUES (v_user, p_quote, p_type, v_date)
    ON CONFLICT (
        user_id, quote_id, interaction_type, interaction_date
    ) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        SELECT id INTO v_id
        FROM public.quote_interactions
        WHERE user_id = v_user
          AND quote_id = p_quote
          AND interaction_type = p_type
          AND interaction_date = v_date;
    END IF;

    RETURN v_id;
END;
$$;

-- 9. Restrict function execution.
REVOKE ALL ON FUNCTION public.trigger_set_timestamp() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_profile_dob() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_owner(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_goal_category_ownership() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_task_ownership() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_custom_theme_limit() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.insert_quote_interaction(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_quote_interaction(uuid, text) TO authenticated;
