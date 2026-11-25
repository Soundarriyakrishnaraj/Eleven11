-- =============================================================================
-- ELEVEN11: READ-ONLY VERIFICATION AFTER MIGRATION 016 (BEFORE 017)
-- =============================================================================

SELECT key, value
FROM public._migration_016_metadata
WHERE key IN ('migration_016_started_at','migration_016_completed_at')
ORDER BY key;

SELECT user_id, role, created_at
FROM public.admin_roles
WHERE user_id='74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a'::uuid;

SELECT c.relname, c.relrowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN ('user_activity_presence','login_history','user_feedback')
ORDER BY c.relname;

SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='user_feedback'
ORDER BY ordinal_position;

SELECT policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('user_feedback','user_activity_presence','login_history')
ORDER BY tablename, policyname;

SELECT routine_name, routine_type, security_type
FROM information_schema.routines
WHERE routine_schema='public'
  AND routine_name IN ('record_user_heartbeat','record_verified_login','admin_activity_summary')
ORDER BY routine_name;

-- Verify ordinary authenticated users CANNOT read admin_note, while service_role CAN.
SELECT
  has_column_privilege('authenticated', 'public.user_feedback', 'admin_note', 'SELECT') AS auth_can_select_admin_note,
  has_column_privilege('authenticated', 'public.user_feedback', 'message', 'SELECT') AS auth_can_select_message,
  has_column_privilege('service_role', 'public.user_feedback', 'admin_note', 'SELECT') AS service_can_select_admin_note,
  has_column_privilege('service_role', 'public.user_feedback', 'admin_note', 'UPDATE') AS service_can_update_admin_note;
