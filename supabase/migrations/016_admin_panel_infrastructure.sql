-- =============================================================================
-- ELEVEN11 MIGRATION 016 — ADMIN PANEL INFRASTRUCTURE
-- Based on the supplied live-schema diagnostics.
-- Creates feedback triage fields, activity presence, login history,
-- restricted RPC functions, and the designated super-admin role.
--
-- RUN THIS FIRST. Run as the Supabase SQL Editor postgres role.
-- Do not run if the preflight checks fail.
-- =============================================================================

BEGIN;
SELECT pg_advisory_xact_lock(pg_catalog.hashtextextended('eleven11:migration:016', 0));

-- -----------------------------------------------------------------------------
-- 0. PREFLIGHT: stop rather than guessing if the live schema differs.
-- -----------------------------------------------------------------------------
DO $preflight$
DECLARE
  v_dtype text;
  v_nullable text;
  v_default text;
  v_pk_count integer;
  v_fk_count integer;
  v_check_count integer;
  v_policy_count integer;
  v_function_owner text;
  v_function_language text;
  v_function_volatility "char";
  v_function_security_definer boolean;
  v_function_return text;
  v_function_config text;
  v_function_definition text;
  v_expected record;
  v_actual text;
  v_name text;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION '[016 preflight] Run this migration as the postgres database role; current_user=%', current_user;
  END IF;

  IF to_regclass('public._migration_016_metadata') IS NOT NULL THEN
    RAISE EXCEPTION '[016 preflight] public._migration_016_metadata already exists. Do not rerun this migration.';
  END IF;
  IF to_regclass('public.user_activity_presence') IS NOT NULL
     OR to_regclass('public.login_history') IS NOT NULL THEN
    RAISE EXCEPTION '[016 preflight] An activity table already exists. Inspect it manually; migration stopped.';
  END IF;
  IF to_regclass('public.profiles') IS NULL
     OR to_regclass('public.admin_roles') IS NULL
     OR to_regclass('public.user_feedback') IS NULL
     OR to_regclass('public.events') IS NULL THEN
    RAISE EXCEPTION '[016 preflight] One or more required base tables are missing.';
  END IF;

  -- Required profiles columns.
  FOR v_expected IN
    SELECT * FROM (VALUES
      ('id', 'uuid', 'NO'),
      ('created_at', 'timestamp with time zone', 'NO'),
      ('deleted_at', 'timestamp with time zone', 'YES')
    ) AS x(column_name, data_type, is_nullable)
  LOOP
    SELECT c.data_type, c.is_nullable INTO v_dtype, v_nullable
    FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name='profiles'
      AND c.column_name=v_expected.column_name;
    IF NOT FOUND OR v_dtype <> v_expected.data_type OR v_nullable <> v_expected.is_nullable THEN
      RAISE EXCEPTION '[016 preflight] profiles.% expected % nullable %, found % nullable %.',
        v_expected.column_name, v_expected.data_type, v_expected.is_nullable, v_dtype, v_nullable;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a'::uuid
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION '[016 preflight] Designated admin UUID is missing from active public.profiles.';
  END IF;

  -- Verify admin_roles column definitions.
  SELECT data_type, is_nullable, column_default INTO v_dtype, v_nullable, v_default
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='admin_roles' AND column_name='user_id';
  IF NOT FOUND OR v_dtype <> 'uuid' OR v_nullable <> 'NO' THEN
    RAISE EXCEPTION '[016 preflight] admin_roles.user_id must be UUID NOT NULL.';
  END IF;
  SELECT data_type, is_nullable, column_default INTO v_dtype, v_nullable, v_default
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='admin_roles' AND column_name='role';
  IF NOT FOUND OR v_dtype <> 'text' OR v_nullable <> 'NO' OR v_default NOT LIKE '%admin%' THEN
    RAISE EXCEPTION '[016 preflight] admin_roles.role definition differs from inspected schema.';
  END IF;

  SELECT count(*) INTO v_pk_count
  FROM pg_constraint c
  WHERE c.conrelid='public.admin_roles'::regclass AND c.contype='p'
    AND c.conkey = ARRAY[(SELECT a.attnum FROM pg_attribute a
                          WHERE a.attrelid='public.admin_roles'::regclass
                            AND a.attname='user_id' AND NOT a.attisdropped)]::smallint[];
  IF v_pk_count <> 1 THEN
    RAISE EXCEPTION '[016 preflight] admin_roles must have a single-column PRIMARY KEY on user_id.';
  END IF;

  SELECT count(*) INTO v_fk_count
  FROM pg_constraint c
  WHERE c.conrelid='public.admin_roles'::regclass
    AND c.contype='f'
    AND c.confrelid='public.profiles'::regclass
    AND c.conkey = ARRAY[(SELECT a.attnum FROM pg_attribute a
                          WHERE a.attrelid='public.admin_roles'::regclass
                            AND a.attname='user_id' AND NOT a.attisdropped)]::smallint[]
    AND c.confkey = ARRAY[(SELECT a.attnum FROM pg_attribute a
                           WHERE a.attrelid='public.profiles'::regclass
                             AND a.attname='id' AND NOT a.attisdropped)]::smallint[]
    AND c.confdeltype='c' AND c.convalidated;
  IF v_fk_count <> 1 THEN
    RAISE EXCEPTION '[016 preflight] admin_roles.user_id must reference public.profiles(id) ON DELETE CASCADE.';
  END IF;

  SELECT count(*) INTO v_check_count
  FROM pg_constraint c
  WHERE c.conrelid='public.admin_roles'::regclass AND c.contype='c'
    AND pg_get_constraintdef(c.oid) ILIKE '%role%admin%super_admin%'
    AND c.convalidated;
  IF v_check_count <> 1 THEN
    RAISE EXCEPTION '[016 preflight] Expected validated admin_roles role CHECK constraint was not found.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id='74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a'::uuid) THEN
    RAISE EXCEPTION '[016 preflight] Designated admin already has an admin_roles row. Review its role; migration will not overwrite it.';
  END IF;

  -- Verify existing is_admin() function rather than replacing it.
  SELECT pg_get_userbyid(p.proowner), l.lanname, p.provolatile,
         p.prosecdef, pg_catalog.format_type(p.prorettype, NULL),
         pg_catalog.array_to_string(p.proconfig, ', '), pg_get_functiondef(p.oid)
    INTO v_function_owner, v_function_language, v_function_volatility,
         v_function_security_definer, v_function_return, v_function_config,
         v_function_definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  JOIN pg_language l ON l.oid=p.prolang
  WHERE n.nspname='public' AND p.proname='is_admin' AND p.pronargs=0;
  IF NOT FOUND
     OR v_function_owner <> 'postgres'
     OR v_function_language <> 'sql'
     OR v_function_volatility <> 's'
     OR v_function_security_definer IS DISTINCT FROM true
     OR v_function_return <> 'boolean'
     OR v_function_config NOT LIKE '%search_path=pg_catalog, public, auth%'
     OR v_function_definition NOT ILIKE '%public.admin_roles%'
     OR v_function_definition NOT ILIKE '%auth.uid()%'
  THEN
    RAISE EXCEPTION '[016 preflight] public.is_admin() does not match the inspected secure function. Migration stopped.';
  END IF;

  -- Verify baseline feedback columns and reject partial/unknown prior migrations.
  FOR v_expected IN
    SELECT * FROM (VALUES
      ('id', 'uuid', 'NO'),
      ('user_id', 'uuid', 'NO'),
      ('message', 'text', 'NO'),
      ('rating', 'integer', 'YES'),
      ('created_at', 'timestamp with time zone', 'NO')
    ) AS x(column_name, data_type, is_nullable)
  LOOP
    SELECT c.data_type, c.is_nullable INTO v_dtype, v_nullable
    FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name='user_feedback'
      AND c.column_name=v_expected.column_name;
    IF NOT FOUND OR v_dtype <> v_expected.data_type OR v_nullable <> v_expected.is_nullable THEN
      RAISE EXCEPTION '[016 preflight] user_feedback.% differs from the inspected base schema.', v_expected.column_name;
    END IF;
  END LOOP;

  FOREACH v_name IN ARRAY ARRAY['category','status','admin_note','updated_at'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='user_feedback' AND column_name=v_name) THEN
      RAISE EXCEPTION '[016 preflight] user_feedback.% already exists; inspect partial migration state.', v_name;
    END IF;
  END LOOP;

  -- The diagnostic showed exactly these two baseline feedback policies. Preserve them.
  SELECT count(*) INTO v_policy_count FROM pg_policies
  WHERE schemaname='public' AND tablename='user_feedback';
  IF v_policy_count <> 2
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='user_feedback'
         AND policyname='user_feedback_select' AND cmd='SELECT'
         AND permissive='PERMISSIVE'
         AND roles=ARRAY['authenticated'::name]
         AND replace(lower(qual), ' ', '')='((user_id=auth.uid())oris_admin())'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='user_feedback'
         AND policyname='user_feedback_insert' AND cmd='INSERT'
         AND permissive='PERMISSIVE'
         AND roles=ARRAY['authenticated'::name]
         AND replace(lower(with_check), ' ', '')='(user_id=auth.uid())'
     ) THEN
    RAISE EXCEPTION '[016 preflight] user_feedback RLS policies differ from the inspected baseline. No policies will be dropped.';
  END IF;

  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.user_feedback'::regclass) THEN
    RAISE EXCEPTION '[016 preflight] RLS is not enabled on user_feedback.';
  END IF;

  -- Check all migration-owned names before creating anything.
  FOREACH v_name IN ARRAY ARRAY[
    'idx_user_feedback_status','idx_user_feedback_user_id','idx_user_feedback_created_at',
    'idx_presence_last_active','idx_presence_last_login','idx_login_history_user_id'
  ] LOOP
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
               WHERE n.nspname='public' AND c.relname=v_name) THEN
      RAISE EXCEPTION '[016 preflight] Relation/index name public.% already exists.', v_name;
    END IF;
  END LOOP;

  FOREACH v_name IN ARRAY ARRAY[
    'trg_feedback_insert_enforce','trg_feedback_update_enforce',
    'record_user_heartbeat','record_verified_login','admin_activity_summary'
  ] LOOP
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname=v_name) THEN
      RAISE EXCEPTION '[016 preflight] Function name public.% already exists.', v_name;
    END IF;
  END LOOP;

  FOREACH v_name IN ARRAY ARRAY[
    'trg_feedback_insert','trg_feedback_update',
    'user_feedback_admin_update_016','presence_select_016','login_history_select_016'
  ] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_trigger t
      JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND t.tgname=v_name AND NOT t.tgisinternal
    ) OR EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname='public' AND p.policyname=v_name
    ) THEN
      RAISE EXCEPTION '[016 preflight] Trigger/policy name % already exists.', v_name;
    END IF;
  END LOOP;
END;
$preflight$;

-- -----------------------------------------------------------------------------
-- 1. MIGRATION METADATA (private to database administrators).
-- -----------------------------------------------------------------------------
CREATE TABLE public._migration_016_metadata (
  key text PRIMARY KEY,
  value text NOT NULL
);
ALTER TABLE public._migration_016_metadata ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public._migration_016_metadata FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO public._migration_016_metadata(key, value) VALUES
  ('migration_016_started_at', now()::text),
  ('admin_seed__prior_role', 'none'),
  ('admin_seed__action', 'inserted');

-- -----------------------------------------------------------------------------
-- 2. FEEDBACK TRIAGE COLUMNS AND EXACT VALUE CONSTRAINTS.
-- -----------------------------------------------------------------------------
ALTER TABLE public.user_feedback
  ADD COLUMN category text NOT NULL DEFAULT 'general',
  ADD COLUMN status text NOT NULL DEFAULT 'new',
  ADD COLUMN admin_note text,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.user_feedback
  ADD CONSTRAINT user_feedback_category_check
    CHECK (category IN ('general','bug_report','feature_request','performance','theme_eink')),
  ADD CONSTRAINT user_feedback_status_check
    CHECK (status IN ('new','reviewed','resolved','dismissed'));

CREATE INDEX idx_user_feedback_status ON public.user_feedback(status);
CREATE INDEX idx_user_feedback_user_id ON public.user_feedback(user_id);
CREATE INDEX idx_user_feedback_created_at ON public.user_feedback(created_at DESC);

-- Prevent users from deleting, reading internal admin notes, or changing other users' feedback.
-- Admins may update only triage fields; the trigger owns updated_at.
REVOKE ALL ON TABLE public.user_feedback FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, user_id, message, rating, category, status, created_at, updated_at)
  ON TABLE public.user_feedback TO authenticated;
GRANT INSERT (user_id, message, rating, category)
  ON TABLE public.user_feedback TO authenticated;
GRANT UPDATE (status, admin_note, updated_at)
  ON TABLE public.user_feedback TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.user_feedback TO service_role;

-- -----------------------------------------------------------------------------
-- 3. FEEDBACK INSERT/UPDATE ENFORCEMENT.
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.trg_feedback_insert_enforce()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_claims jsonb := auth.jwt();
  v_role text := v_claims ->> 'role';
  v_uid uuid := auth.uid();
BEGIN
  IF v_role = 'authenticated' AND v_uid IS NOT NULL THEN
    NEW.user_id := v_uid;
    NEW.category := COALESCE(NEW.category, 'general');
    NEW.status := 'new';
    NEW.admin_note := NULL;
    NEW.created_at := pg_catalog.now();
    NEW.updated_at := pg_catalog.now();
    IF NEW.message IS NULL OR pg_catalog.length(pg_catalog.btrim(NEW.message)) = 0 THEN
      RAISE EXCEPTION 'Feedback message cannot be empty.';
    END IF;
    RETURN NEW;
  ELSIF v_role = 'service_role' OR (SESSION_USER = 'postgres' AND v_claims IS NULL) THEN
    NEW.category := COALESCE(NEW.category, 'general');
    NEW.status := COALESCE(NEW.status, 'new');
    NEW.created_at := COALESCE(NEW.created_at, pg_catalog.now());
    NEW.updated_at := pg_catalog.now();
    IF NEW.message IS NULL OR pg_catalog.length(pg_catalog.btrim(NEW.message)) = 0 THEN
      RAISE EXCEPTION 'Feedback message cannot be empty.';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Feedback insert rejected: unsupported authentication context.';
END;
$function$;

CREATE FUNCTION public.trg_feedback_update_enforce()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_claims jsonb := auth.jwt();
  v_role text := v_claims ->> 'role';
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.message IS DISTINCT FROM OLD.message
     OR NEW.rating IS DISTINCT FROM OLD.rating
     OR NEW.category IS DISTINCT FROM OLD.category
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Feedback identity and submitted content are immutable.';
  END IF;

  IF v_role = 'authenticated' THEN
    IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Only administrators may update feedback triage fields.';
    END IF;
  ELSIF (v_role IS DISTINCT FROM 'service_role')
        AND NOT (SESSION_USER = 'postgres' AND v_claims IS NULL) THEN
    RAISE EXCEPTION 'Feedback update rejected: unsupported authentication context.';
  END IF;

  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_feedback_insert
  BEFORE INSERT ON public.user_feedback
  FOR EACH ROW EXECUTE FUNCTION public.trg_feedback_insert_enforce();
CREATE TRIGGER trg_feedback_update
  BEFORE UPDATE ON public.user_feedback
  FOR EACH ROW EXECUTE FUNCTION public.trg_feedback_update_enforce();

REVOKE ALL ON FUNCTION public.trg_feedback_insert_enforce() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.trg_feedback_update_enforce() FROM PUBLIC, anon, authenticated, service_role;

-- Keep the two inspected baseline policies unchanged; add only admin UPDATE.
CREATE POLICY user_feedback_admin_update_016
  ON public.user_feedback
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- -----------------------------------------------------------------------------
-- 4. ACTIVITY PRESENCE AND LOGIN HISTORY TABLES.
-- -----------------------------------------------------------------------------
CREATE TABLE public.user_activity_presence (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_active_at timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz,
  app_version text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_activity_presence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.user_activity_presence FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.user_activity_presence TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.user_activity_presence TO service_role;
CREATE POLICY presence_select_016
  ON public.user_activity_presence
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
CREATE INDEX idx_presence_last_active ON public.user_activity_presence(last_active_at DESC);
CREATE INDEX idx_presence_last_login ON public.user_activity_presence(last_login_at DESC);

CREATE TABLE public.login_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  logged_in_at timestamptz NOT NULL DEFAULT now(),
  app_version text
);
ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.login_history FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.login_history TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.login_history TO service_role;
-- Explicit identity-sequence access for backend service-role inserts.
REVOKE ALL ON SEQUENCE public.login_history_id_seq FROM PUBLIC, anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.login_history_id_seq TO service_role;
CREATE POLICY login_history_select_016
  ON public.login_history
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
CREATE INDEX idx_login_history_user_id ON public.login_history(user_id, logged_in_at DESC);

-- -----------------------------------------------------------------------------
-- 5. SECURE ACTIVITY RPC FUNCTIONS.
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.record_user_heartbeat(p_app_version text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_role text := auth.jwt() ->> 'role';
  v_uid uuid := auth.uid();
BEGIN
  IF v_role IS DISTINCT FROM 'authenticated' OR v_uid IS NULL THEN
    RAISE EXCEPTION 'record_user_heartbeat requires an authenticated user token.';
  END IF;

  INSERT INTO public.user_activity_presence(user_id, last_active_at, app_version)
  VALUES (v_uid, pg_catalog.now(), p_app_version)
  ON CONFLICT (user_id) DO UPDATE
    SET last_active_at = EXCLUDED.last_active_at,
        app_version = COALESCE(EXCLUDED.app_version, public.user_activity_presence.app_version);
END;
$function$;
ALTER FUNCTION public.record_user_heartbeat(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_user_heartbeat(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_user_heartbeat(text) TO authenticated;

CREATE FUNCTION public.record_verified_login(p_user_id uuid, p_app_version text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_role text := auth.jwt() ->> 'role';
  v_now timestamptz := pg_catalog.now();
BEGIN
  IF (v_role IS DISTINCT FROM 'service_role')
     AND NOT (SESSION_USER = 'postgres' AND auth.jwt() IS NULL) THEN
    RAISE EXCEPTION 'record_verified_login requires a trusted server-side caller.';
  END IF;
  IF p_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id=p_user_id AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'record_verified_login received an unknown or inactive user.';
  END IF;

  INSERT INTO public.login_history(user_id, logged_in_at, app_version)
  VALUES (p_user_id, v_now, p_app_version);

  INSERT INTO public.user_activity_presence(user_id, last_active_at, last_login_at, app_version)
  VALUES (p_user_id, v_now, v_now, p_app_version)
  ON CONFLICT (user_id) DO UPDATE
    SET last_active_at = EXCLUDED.last_active_at,
        last_login_at = EXCLUDED.last_login_at,
        app_version = COALESCE(EXCLUDED.app_version, public.user_activity_presence.app_version);
END;
$function$;
ALTER FUNCTION public.record_verified_login(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_verified_login(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_verified_login(uuid, text) TO service_role;

CREATE FUNCTION public.admin_activity_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_utc_midnight timestamptz :=
    pg_catalog.date_trunc('day', pg_catalog.now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_summary jsonb;
BEGIN
  IF public.is_admin() IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'admin_activity_summary: administrator authorization required.';
  END IF;

  SELECT pg_catalog.jsonb_build_object(
    'dau', (SELECT count(*) FROM public.user_activity_presence WHERE last_active_at >= v_utc_midnight),
    'wau', (SELECT count(*) FROM public.user_activity_presence WHERE last_active_at >= pg_catalog.now() - interval '7 days'),
    'mau', (SELECT count(*) FROM public.user_activity_presence WHERE last_active_at >= pg_catalog.now() - interval '30 days'),
    'active_15min', (SELECT count(*) FROM public.user_activity_presence WHERE last_active_at >= pg_catalog.now() - interval '15 minutes'),
    'total_presence_records', (SELECT count(*) FROM public.user_activity_presence),
    'total_users', (SELECT count(*) FROM public.profiles WHERE deleted_at IS NULL),
    'new_registrations_today', (SELECT count(*) FROM public.profiles WHERE created_at >= v_utc_midnight AND deleted_at IS NULL),
    'new_registrations_7d', (SELECT count(*) FROM public.profiles WHERE created_at >= pg_catalog.now() - interval '7 days' AND deleted_at IS NULL),
    'new_registrations_30d', (SELECT count(*) FROM public.profiles WHERE created_at >= pg_catalog.now() - interval '30 days' AND deleted_at IS NULL),
    'total_events', (SELECT count(*) FROM public.events),
    'total_feedback', (SELECT count(*) FROM public.user_feedback),
    'total_logins', (SELECT count(*) FROM public.login_history),
    'total_logouts', NULL::bigint,
    'total_session_expiries', NULL::bigint,
    'generated_at', pg_catalog.now()
  ) INTO v_summary;

  RETURN v_summary;
END;
$function$;
ALTER FUNCTION public.admin_activity_summary() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_activity_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activity_summary() TO authenticated;

-- -----------------------------------------------------------------------------
-- 6. SEED the designated admin only after confirming no existing row.
-- -----------------------------------------------------------------------------
INSERT INTO public.admin_roles(user_id, role)
VALUES ('74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a'::uuid, 'super_admin');

DO $verify_admin$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_roles
    WHERE user_id='74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a'::uuid
      AND role='super_admin'
  ) THEN
    RAISE EXCEPTION '[016 verify] Designated administrator seed did not verify.';
  END IF;
END;
$verify_admin$;

-- -----------------------------------------------------------------------------
-- 7. Record exact definitions for guarded rollback and completion marker.
-- -----------------------------------------------------------------------------
INSERT INTO public._migration_016_metadata(key, value)
SELECT 'functiondef__' || p.proname, pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN (
    'trg_feedback_insert_enforce','trg_feedback_update_enforce',
    'record_user_heartbeat','record_verified_login','admin_activity_summary'
  );

INSERT INTO public._migration_016_metadata(key, value)
SELECT 'indexdef__' || indexname, indexdef
FROM pg_indexes
WHERE schemaname='public'
  AND indexname IN (
    'idx_user_feedback_status','idx_user_feedback_user_id','idx_user_feedback_created_at',
    'idx_presence_last_active','idx_presence_last_login','idx_login_history_user_id'
  );

INSERT INTO public._migration_016_metadata(key, value)
SELECT 'policydef__' || policyname,
       pg_catalog.jsonb_build_object(
         'policyname', policyname, 'permissive', permissive, 'roles', roles,
         'cmd', cmd, 'qual', qual, 'with_check', with_check
       )::text
FROM pg_policies
WHERE schemaname='public'
  AND policyname IN ('user_feedback_admin_update_016','presence_select_016','login_history_select_016');

INSERT INTO public._migration_016_metadata(key, value)
SELECT 'triggerdef__' || t.tgname, pg_get_triggerdef(t.oid)
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND NOT t.tgisinternal
  AND t.tgname IN ('trg_feedback_insert','trg_feedback_update');

INSERT INTO public._migration_016_metadata(key, value)
VALUES ('migration_016_completed_at', now()::text);

COMMIT;

-- =============================================================================
-- END MIGRATION 016
-- After success, run the separate 016 verification query before Migration 017.
-- =============================================================================
