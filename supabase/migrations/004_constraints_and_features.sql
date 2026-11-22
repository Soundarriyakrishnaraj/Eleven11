
-- Eleven11: Indexes and database triggers

-- 1. Additional indexes.
CREATE INDEX IF NOT EXISTS idx_goals_user_status
ON public.goals(user_id, status);

CREATE INDEX IF NOT EXISTS idx_tasks_due_date
ON public.tasks(user_id, due_date);

CREATE INDEX IF NOT EXISTS idx_quote_interactions_user_date
ON public.quote_interactions(user_id, interaction_date);

CREATE INDEX IF NOT EXISTS idx_user_achievements_user
ON public.user_achievements(user_id);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user
ON public.device_tokens(user_id);

CREATE INDEX IF NOT EXISTS idx_custom_themes_user
ON public.custom_themes(user_id);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_user
ON public.notification_preferences(user_id);

CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_expiry
ON public.password_reset_tokens(expires_at);

-- 2. Automatically update updated_at.
DO $$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'profiles',
        'onboarding',
        'motivation_categories',
        'quotes',
        'user_quote_preferences',
        'goal_categories',
        'goals',
        'tasks',
        'task_reminders',
        'streaks',
        'notification_preferences',
        'device_tokens',
        'custom_themes'
    ]
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS set_timestamp ON public.%I',
            v_table
        );

        EXECUTE format(
            'CREATE TRIGGER set_timestamp
             BEFORE UPDATE ON public.%I
             FOR EACH ROW
             EXECUTE FUNCTION public.trigger_set_timestamp()',
            v_table
        );
    END LOOP;
END;
$$;

-- 3. Validate date of birth.
DROP TRIGGER IF EXISTS validate_profile_dob ON public.profiles;

CREATE TRIGGER validate_profile_dob
BEFORE INSERT OR UPDATE OF date_of_birth
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.validate_profile_dob();

-- 4. Validate goal category ownership.
DROP TRIGGER IF EXISTS enforce_goal_category_owner ON public.goals;

CREATE TRIGGER enforce_goal_category_owner
BEFORE INSERT OR UPDATE OF category_id, user_id
ON public.goals
FOR EACH ROW
EXECUTE FUNCTION public.enforce_goal_category_ownership();

-- 5. Enforce task ownership.
DROP TRIGGER IF EXISTS enforce_task_owner ON public.tasks;

CREATE TRIGGER enforce_task_owner
BEFORE INSERT OR UPDATE
ON public.tasks
FOR EACH ROW
EXECUTE FUNCTION public.enforce_task_ownership();

-- 6. Enforce maximum five custom themes per user.
DROP TRIGGER IF EXISTS enforce_theme_limit ON public.custom_themes;

CREATE TRIGGER enforce_theme_limit
BEFORE INSERT OR UPDATE OF user_id
ON public.custom_themes
FOR EACH ROW
EXECUTE FUNCTION public.enforce_custom_theme_limit();
