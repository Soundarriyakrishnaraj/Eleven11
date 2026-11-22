
-- Eleven11: Row Level Security

-- Enable RLS on all application tables.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.motivation_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_quote_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goal_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_themes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.password_reset_tokens ENABLE ROW LEVEL SECURITY;

-- Remove only Eleven11 policy names when reapplying this migration.
DROP POLICY IF EXISTS profiles_select ON public.profiles;
DROP POLICY IF EXISTS profiles_insert ON public.profiles;
DROP POLICY IF EXISTS profiles_update ON public.profiles;
DROP POLICY IF EXISTS onboarding_select ON public.onboarding;
DROP POLICY IF EXISTS onboarding_insert ON public.onboarding;
DROP POLICY IF EXISTS onboarding_update ON public.onboarding;
DROP POLICY IF EXISTS motivation_categories_select ON public.motivation_categories;
DROP POLICY IF EXISTS motivation_categories_admin ON public.motivation_categories;
DROP POLICY IF EXISTS quotes_select ON public.quotes;
DROP POLICY IF EXISTS quotes_admin ON public.quotes;
DROP POLICY IF EXISTS quote_preferences_select ON public.user_quote_preferences;
DROP POLICY IF EXISTS quote_preferences_insert ON public.user_quote_preferences;
DROP POLICY IF EXISTS quote_preferences_update ON public.user_quote_preferences;
DROP POLICY IF EXISTS quote_preferences_delete ON public.user_quote_preferences;
DROP POLICY IF EXISTS quote_favorites_select ON public.quote_favorites;
DROP POLICY IF EXISTS quote_favorites_insert ON public.quote_favorites;
DROP POLICY IF EXISTS quote_favorites_delete ON public.quote_favorites;
DROP POLICY IF EXISTS quote_interactions_select ON public.quote_interactions;
DROP POLICY IF EXISTS goal_categories_select ON public.goal_categories;
DROP POLICY IF EXISTS goal_categories_insert ON public.goal_categories;
DROP POLICY IF EXISTS goal_categories_update ON public.goal_categories;
DROP POLICY IF EXISTS goal_categories_delete ON public.goal_categories;
DROP POLICY IF EXISTS goal_categories_admin_manage ON public.goal_categories;
DROP POLICY IF EXISTS goals_select ON public.goals;
DROP POLICY IF EXISTS goals_insert ON public.goals;
DROP POLICY IF EXISTS goals_update ON public.goals;
DROP POLICY IF EXISTS goals_delete ON public.goals;
DROP POLICY IF EXISTS tasks_select ON public.tasks;
DROP POLICY IF EXISTS tasks_insert ON public.tasks;
DROP POLICY IF EXISTS tasks_update ON public.tasks;
DROP POLICY IF EXISTS tasks_delete ON public.tasks;
DROP POLICY IF EXISTS task_reminders_select ON public.task_reminders;
DROP POLICY IF EXISTS task_reminders_insert ON public.task_reminders;
DROP POLICY IF EXISTS task_reminders_update ON public.task_reminders;
DROP POLICY IF EXISTS task_reminders_delete ON public.task_reminders;
DROP POLICY IF EXISTS streaks_select ON public.streaks;
DROP POLICY IF EXISTS achievements_select ON public.achievements;
DROP POLICY IF EXISTS achievements_admin ON public.achievements;
DROP POLICY IF EXISTS user_achievements_select ON public.user_achievements;
DROP POLICY IF EXISTS notification_preferences_select ON public.notification_preferences;
DROP POLICY IF EXISTS notification_preferences_insert ON public.notification_preferences;
DROP POLICY IF EXISTS notification_preferences_update ON public.notification_preferences;
DROP POLICY IF EXISTS notification_preferences_delete ON public.notification_preferences;
DROP POLICY IF EXISTS device_tokens_select ON public.device_tokens;
DROP POLICY IF EXISTS device_tokens_insert ON public.device_tokens;
DROP POLICY IF EXISTS device_tokens_update ON public.device_tokens;
DROP POLICY IF EXISTS device_tokens_delete ON public.device_tokens;
DROP POLICY IF EXISTS custom_themes_select ON public.custom_themes;
DROP POLICY IF EXISTS custom_themes_insert ON public.custom_themes;
DROP POLICY IF EXISTS custom_themes_update ON public.custom_themes;
DROP POLICY IF EXISTS custom_themes_delete ON public.custom_themes;
DROP POLICY IF EXISTS user_feedback_select ON public.user_feedback;
DROP POLICY IF EXISTS user_feedback_insert ON public.user_feedback;
DROP POLICY IF EXISTS user_ratings_select ON public.user_ratings;
DROP POLICY IF EXISTS user_ratings_insert ON public.user_ratings;
DROP POLICY IF EXISTS admin_audit_logs_select ON public.admin_audit_logs;

-- Profiles
CREATE POLICY profiles_select ON public.profiles
FOR SELECT TO authenticated
USING (id = auth.uid() OR public.is_admin());

CREATE POLICY profiles_insert ON public.profiles
FOR INSERT TO authenticated
WITH CHECK (id = auth.uid());

CREATE POLICY profiles_update ON public.profiles
FOR UPDATE TO authenticated
USING (id = auth.uid() OR public.is_admin())
WITH CHECK (id = auth.uid() OR public.is_admin());

-- Onboarding
CREATE POLICY onboarding_select ON public.onboarding
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY onboarding_insert ON public.onboarding
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY onboarding_update ON public.onboarding
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Motivation categories
CREATE POLICY motivation_categories_select ON public.motivation_categories
FOR SELECT TO authenticated
USING (is_active = true OR public.is_admin());

CREATE POLICY motivation_categories_admin ON public.motivation_categories
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Quotes
CREATE POLICY quotes_select ON public.quotes
FOR SELECT TO authenticated
USING (is_active = true OR public.is_admin());

CREATE POLICY quotes_admin ON public.quotes
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- User quote preferences
CREATE POLICY quote_preferences_select ON public.user_quote_preferences
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY quote_preferences_insert ON public.user_quote_preferences
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY quote_preferences_update ON public.user_quote_preferences
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY quote_preferences_delete ON public.user_quote_preferences
FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- Quote favorites
CREATE POLICY quote_favorites_select ON public.quote_favorites
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY quote_favorites_insert ON public.quote_favorites
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY quote_favorites_delete ON public.quote_favorites
FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- Quote interactions: insert only through secure RPC.
CREATE POLICY quote_interactions_select ON public.quote_interactions
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

-- Goal categories
CREATE POLICY goal_categories_select ON public.goal_categories
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR user_id IS NULL OR public.is_admin());

CREATE POLICY goal_categories_insert ON public.goal_categories
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY goal_categories_update ON public.goal_categories
FOR UPDATE TO authenticated
USING (user_id = auth.uid() OR public.is_admin())
WITH CHECK (user_id = auth.uid() OR public.is_admin());

CREATE POLICY goal_categories_delete ON public.goal_categories
FOR DELETE TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY goal_categories_admin_manage ON public.goal_categories
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Goals
CREATE POLICY goals_select ON public.goals
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY goals_insert ON public.goals
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY goals_update ON public.goals
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY goals_delete ON public.goals
FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- Tasks
CREATE POLICY tasks_select ON public.tasks
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY tasks_insert ON public.tasks
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY tasks_update ON public.tasks
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY tasks_delete ON public.tasks
FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- Task reminders
CREATE POLICY task_reminders_select ON public.task_reminders
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = task_reminders.task_id
          AND t.user_id = auth.uid()
    )
);

CREATE POLICY task_reminders_insert ON public.task_reminders
FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = task_reminders.task_id
          AND t.user_id = auth.uid()
    )
);

CREATE POLICY task_reminders_update ON public.task_reminders
FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = task_reminders.task_id
          AND t.user_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = task_reminders.task_id
          AND t.user_id = auth.uid()
    )
);

CREATE POLICY task_reminders_delete ON public.task_reminders
FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = task_reminders.task_id
          AND t.user_id = auth.uid()
    )
);

-- Streaks: server-managed writes only.
CREATE POLICY streaks_select ON public.streaks
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

-- Achievements
CREATE POLICY achievements_select ON public.achievements
FOR SELECT TO authenticated
USING (is_active = true OR public.is_admin());

CREATE POLICY achievements_admin ON public.achievements
FOR ALL TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- User achievements: server-managed writes only.
CREATE POLICY user_achievements_select ON public.user_achievements
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

-- Notification preferences
CREATE POLICY notification_preferences_select ON public.notification_preferences
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY notification_preferences_insert ON public.notification_preferences
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY notification_preferences_update ON public.notification_preferences
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY notification_preferences_delete ON public.notification_preferences
FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- Device tokens
CREATE POLICY device_tokens_select ON public.device_tokens
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY device_tokens_insert ON public.device_tokens
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY device_tokens_update ON public.device_tokens
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY device_tokens_delete ON public.device_tokens
FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- Custom themes
CREATE POLICY custom_themes_select ON public.custom_themes
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY custom_themes_insert ON public.custom_themes
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY custom_themes_update ON public.custom_themes
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY custom_themes_delete ON public.custom_themes
FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- Feedback
CREATE POLICY user_feedback_select ON public.user_feedback
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY user_feedback_insert ON public.user_feedback
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

-- Ratings
CREATE POLICY user_ratings_select ON public.user_ratings
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY user_ratings_insert ON public.user_ratings
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

-- Admin roles: no client access.
REVOKE ALL ON TABLE public.admin_roles FROM anon, authenticated;

-- Audit logs: admins can read; server functions write.
CREATE POLICY admin_audit_logs_select ON public.admin_audit_logs
FOR SELECT TO authenticated
USING (public.is_admin());

-- Password reset tokens: Edge Functions/service role only.
REVOKE ALL ON TABLE public.password_reset_tokens FROM anon, authenticated;

-- Table privileges. RLS still controls which rows users can access.
GRANT SELECT, INSERT, UPDATE, DELETE ON
    public.profiles,
    public.onboarding,
    public.motivation_categories,
    public.quotes,
    public.user_quote_preferences,
    public.quote_favorites,
    public.quote_interactions,
    public.goal_categories,
    public.goals,
    public.tasks,
    public.task_reminders,
    public.streaks,
    public.achievements,
    public.user_achievements,
    public.notification_preferences,
    public.device_tokens,
    public.custom_themes,
    public.user_feedback,
    public.user_ratings,
    public.admin_audit_logs
TO authenticated;

-- Remove direct writes to server-managed tables.
REVOKE INSERT, UPDATE, DELETE ON
    public.quote_interactions,
    public.streaks,
    public.user_achievements,
    public.admin_audit_logs
FROM authenticated;

-- Ensure sensitive tables remain inaccessible to client roles.
REVOKE ALL ON TABLE public.admin_roles FROM anon, authenticated;
REVOKE ALL ON TABLE public.password_reset_tokens FROM anon, authenticated;
