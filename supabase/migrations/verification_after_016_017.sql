-- =============================================================================
-- ELEVEN11 POST-MIGRATION VERIFICATION (read-only)
-- Run after Migration 016 and Migration 017 have both completed.
-- =============================================================================

-- 1. Migration markers
SELECT key, value
FROM public._migration_016_metadata
WHERE key IN (
  'migration_016_started_at','migration_016_completed_at',
  'migration_017_started_at','migration_017_completed_at'
)
ORDER BY key;

-- 2. Designated admin role
SELECT user_id, role, created_at
FROM public.admin_roles
WHERE user_id='74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a'::uuid;

-- 3. New tables and RLS
SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN ('user_activity_presence','login_history','user_feedback','events')
ORDER BY c.relname;

-- 4. Feedback columns and constraints
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='user_feedback'
ORDER BY ordinal_position;
SELECT conname, contype, convalidated, pg_get_constraintdef(oid) AS definition
FROM pg_constraint WHERE conrelid='public.user_feedback'::regclass
ORDER BY conname;

-- 5. Migration-created policies plus original event policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('user_feedback','user_activity_presence','login_history','events')
ORDER BY tablename, policyname;

-- 6. Login event types and indexes
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='login_history'
ORDER BY ordinal_position;
SELECT event_type, count(*) AS rows
FROM public.login_history
GROUP BY event_type
ORDER BY event_type;
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname='public'
  AND tablename IN ('user_feedback','user_activity_presence','login_history')
ORDER BY tablename, indexname;

-- 7. Function signatures and permissions
SELECT p.oid::regprocedure::text AS function_signature,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       p.proconfig AS settings,
       p.proacl AS permissions
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('is_admin','record_user_heartbeat','record_verified_login','admin_activity_summary')
ORDER BY p.proname;

-- 8. Aggregate data overview (no user content returned)
SELECT
  (SELECT count(*) FROM public.profiles WHERE deleted_at IS NULL) AS total_users,
  (SELECT count(*) FROM public.events) AS total_events,
  (SELECT count(*) FROM public.user_feedback) AS total_feedback,
  (SELECT count(*) FROM public.user_activity_presence) AS users_with_presence,
  (SELECT count(*) FROM public.login_history WHERE event_type='login') AS total_logins,
  (SELECT count(*) FROM public.login_history WHERE event_type='logout') AS total_logouts,
  (SELECT count(*) FROM public.login_history WHERE event_type='session_expired') AS total_session_expiries;

-- 9. Column-level privilege verification (ordinary users MUST NOT read admin_note)
SELECT
  has_column_privilege('authenticated', 'public.user_feedback', 'admin_note', 'SELECT') AS auth_can_select_admin_note,
  has_column_privilege('authenticated', 'public.user_feedback', 'message', 'SELECT') AS auth_can_select_message,
  has_column_privilege('service_role', 'public.user_feedback', 'admin_note', 'SELECT') AS service_can_select_admin_note,
  has_column_privilege('service_role', 'public.user_feedback', 'admin_note', 'UPDATE') AS service_can_update_admin_note;
