-- 003_add_constraints_and_extra_columns.sql
-- Additional constraints, unique indexes, and goal/task enhancements

-- Ensure unique user preferences per category
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_quote_preferences
    ON user_quote_preferences(user_id, category_id);

-- Ensure unique favorite quotes per user
CREATE UNIQUE INDEX IF NOT EXISTS uq_favorite_quotes
    ON favorite_quotes(user_id, quote_id);

-- Ensure unique user achievements per achievement
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_achievements
    ON user_achievements(user_id, achievement_id);

-- Ensure each notification preference (channel) is stored once per user
CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_preferences
    ON notification_preferences(user_id, channel);

-- Extend goals table with start_date, reason, progress fields
ALTER TABLE goals
    ADD COLUMN IF NOT EXISTS start_date date,
    ADD COLUMN IF NOT EXISTS reason text,
    ADD COLUMN IF NOT EXISTS progress numeric DEFAULT 0 CHECK (progress >= 0);

-- Ensure start_date is NOT NULL when goal is created (enforced via app), but DB level we keep optional.

-- Modify tasks: allow independent ownership (user_id) and optional goal_id
ALTER TABLE tasks
    ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;

-- Add a check that either user_id is set OR goal_id is set
ALTER TABLE tasks
    ADD CONSTRAINT chk_task_ownership CHECK (
        user_id IS NOT NULL OR goal_id IS NOT NULL
    );

-- Add unique daily interaction constraint for quote_interactions
-- First, add a generated column for interaction_date (UTC)
ALTER TABLE quote_interactions
    ADD COLUMN IF NOT EXISTS interaction_date date GENERATED ALWAYS AS (date(created_at)) STORED;

CREATE UNIQUE INDEX IF NOT EXISTS uq_daily_interaction
    ON quote_interactions(user_id, quote_id, interaction_type, interaction_date);

-- Add timezone column to streaks for accurate day boundaries
ALTER TABLE streaks
    ADD COLUMN IF NOT EXISTS tz text NOT NULL DEFAULT 'UTC';

-- Add triggers for tables missing updated_at handling
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN (
        'onboarding_responses','user_quote_preferences','favorite_quotes','quote_interactions',
        'goals','goal_categories','tasks','task_reminders','user_feedback','user_ratings','password_reset_tokens'
    ) LOOP
        EXECUTE format('CREATE TRIGGER set_timestamp_%I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();', r.tablename, r.tablename);
    END LOOP;
END $$;

COMMIT;
