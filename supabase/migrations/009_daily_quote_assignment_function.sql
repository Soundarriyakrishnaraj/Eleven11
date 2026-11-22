CREATE OR REPLACE FUNCTION public.get_or_assign_daily_quote(
    p_local_date date
)
RETURNS TABLE (quote_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_quote_id uuid;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT d.quote_id
    INTO v_quote_id
    FROM public.daily_quote_assignments d
    WHERE d.user_id = v_user_id
      AND d.assigned_date = p_local_date;

    IF v_quote_id IS NULL THEN
        SELECT q.id
        INTO v_quote_id
        FROM public.quotes q
        JOIN public.user_selected_categories c
          ON c.category_id = q.category_id
        WHERE c.user_id = v_user_id
          AND q.is_active = true
        ORDER BY md5(
            q.id::text || v_user_id::text || p_local_date::text
        )
        LIMIT 1;

        IF v_quote_id IS NULL THEN
            RETURN;
        END IF;

        INSERT INTO public.daily_quote_assignments
            (user_id, quote_id, assigned_date)
        VALUES
            (v_user_id, v_quote_id, p_local_date)
        ON CONFLICT DO NOTHING;

        SELECT d.quote_id
        INTO v_quote_id
        FROM public.daily_quote_assignments d
        WHERE d.user_id = v_user_id
          AND d.assigned_date = p_local_date;
    END IF;

    RETURN QUERY SELECT v_quote_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_or_assign_daily_quote(date)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_or_assign_daily_quote(date)
TO authenticated;