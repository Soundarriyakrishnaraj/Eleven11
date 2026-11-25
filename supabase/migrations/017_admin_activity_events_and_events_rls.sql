-- =============================================================================
-- ELEVEN11 MIGRATION 017 — LOGIN/LOGOUT/SESSION-EXPIRY EVENT TYPES
--                          AND ADMIN READ POLICY ON public.events
-- Prerequisite: Migration 016 completed successfully.
-- Does not replace or drop the four existing user-isolation event policies.
-- =============================================================================

BEGIN;
SELECT pg_advisory_xact_lock(pg_catalog.hashtextextended('eleven11:migration:017', 0));

DO $preflight$
DECLARE
  v_count integer;
  v_definition text;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION '[017 preflight] Run as the postgres database role; current_user=%', current_user;
  END IF;
  IF to_regclass('public._migration_016_metadata') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public._migration_016_metadata
       WHERE key='migration_016_completed_at'
     ) THEN
    RAISE EXCEPTION '[017 preflight] Migration 016 completion marker is missing.';
  END IF;
  IF to_regclass('public.login_history') IS NULL OR to_regclass('public.events') IS NULL THEN
    RAISE EXCEPTION '[017 preflight] Required login_history/events table is missing.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='login_history' AND column_name='event_type'
  ) THEN
    RAISE EXCEPTION '[017 preflight] login_history.event_type already exists; inspect partial migration state.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.login_history'::regclass AND conname='login_history_event_type_check'
  ) THEN
    RAISE EXCEPTION '[017 preflight] login_history_event_type_check already exists.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='idx_login_history_event_type'
  ) THEN
    RAISE EXCEPTION '[017 preflight] idx_login_history_event_type already exists.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='events' AND policyname='events_admin_read_017'
  ) THEN
    RAISE EXCEPTION '[017 preflight] events_admin_read_017 already exists.';
  END IF;

  -- Verify exact definitions of all four existing owner-isolation policies.
  SELECT count(*) INTO v_count FROM pg_policies
  WHERE schemaname='public' AND tablename='events';
  IF v_count <> 4
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='events'
         AND policyname='events_user_isolation_select' AND cmd='SELECT'
         AND permissive='PERMISSIVE'
         AND replace(lower(qual), ' ', '')='(auth.uid()=user_id)'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='events'
         AND policyname='events_user_isolation_insert' AND cmd='INSERT'
         AND permissive='PERMISSIVE'
         AND replace(lower(with_check), ' ', '')='(auth.uid()=user_id)'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='events'
         AND policyname='events_user_isolation_update' AND cmd='UPDATE'
         AND permissive='PERMISSIVE'
         AND replace(lower(qual), ' ', '')='(auth.uid()=user_id)'
         AND replace(lower(with_check), ' ', '')='(auth.uid()=user_id)'
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='events'
         AND policyname='events_user_isolation_delete' AND cmd='DELETE'
         AND permissive='PERMISSIVE'
         AND replace(lower(qual), ' ', '')='(auth.uid()=user_id)'
     ) THEN
    RAISE EXCEPTION '[017 preflight] Existing events RLS policy set differs from inspected baseline. No policies will be dropped.';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.events'::regclass) THEN
    RAISE EXCEPTION '[017 preflight] RLS is not enabled on public.events.';
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_definition
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='admin_activity_summary' AND p.pronargs=0;
  IF NOT FOUND OR v_definition IS NULL THEN
    RAISE EXCEPTION '[017 preflight] public.admin_activity_summary() from Migration 016 is missing.';
  END IF;
END;
$preflight$;

-- Preserve the previous function definition for guarded rollback.
INSERT INTO public._migration_016_metadata(key, value)
SELECT 'migration_017_admin_activity_summary_before', pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='admin_activity_summary' AND p.pronargs=0;
INSERT INTO public._migration_016_metadata(key, value)
VALUES ('migration_017_started_at', now()::text);

-- Existing rows are classified as login. New events can record logout/session_expired.
ALTER TABLE public.login_history
  ADD COLUMN event_type text NOT NULL DEFAULT 'login';
ALTER TABLE public.login_history
  ADD CONSTRAINT login_history_event_type_check
  CHECK (event_type IN ('login','logout','session_expired'));
CREATE INDEX idx_login_history_event_type
  ON public.login_history(event_type, logged_in_at DESC);

-- Add a separate admin SELECT policy. Preserve all four user-isolation policies.
CREATE POLICY events_admin_read_017
  ON public.events
  FOR SELECT TO authenticated
  USING (public.is_admin());

-- Return real login/logout/expiry totals now that event_type exists.
CREATE OR REPLACE FUNCTION public.admin_activity_summary()
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
    'total_logins', (SELECT count(*) FROM public.login_history WHERE event_type='login'),
    'total_logouts', (SELECT count(*) FROM public.login_history WHERE event_type='logout'),
    'total_session_expiries', (SELECT count(*) FROM public.login_history WHERE event_type='session_expired'),
    'generated_at', pg_catalog.now()
  ) INTO v_summary;

  RETURN v_summary;
END;
$function$;
ALTER FUNCTION public.admin_activity_summary() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_activity_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activity_summary() TO authenticated;

-- Save created definitions and a completion marker.
INSERT INTO public._migration_016_metadata(key, value)
SELECT 'migration_017_admin_activity_summary_after', pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='admin_activity_summary' AND p.pronargs=0;
INSERT INTO public._migration_016_metadata(key, value)
SELECT 'migration_017_indexdef', indexdef
FROM pg_indexes
WHERE schemaname='public' AND indexname='idx_login_history_event_type';
INSERT INTO public._migration_016_metadata(key, value)
SELECT 'migration_017_policydef',
       pg_catalog.jsonb_build_object(
         'policyname', policyname, 'permissive', permissive, 'roles', roles,
         'cmd', cmd, 'qual', qual, 'with_check', with_check
       )::text
FROM pg_policies
WHERE schemaname='public' AND tablename='events' AND policyname='events_admin_read_017';
INSERT INTO public._migration_016_metadata(key, value)
VALUES ('migration_017_completed_at', now()::text);

COMMIT;

-- =============================================================================
-- END MIGRATION 017
-- =============================================================================
