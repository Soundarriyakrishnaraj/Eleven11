
-- Eleven11: Core database schema
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Profiles
CREATE TABLE IF NOT EXISTS public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name text,
    avatar_url text,
    date_of_birth date,
    tz text NOT NULL DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_profiles_full_name
ON public.profiles(full_name);

-- 2. Onboarding
CREATE TABLE IF NOT EXISTS public.onboarding (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    question_key text NOT NULL,
    answer jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, question_key)
);

-- 3. Motivation categories
CREATE TABLE IF NOT EXISTS public.motivation_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- 4. Quotes
CREATE TABLE IF NOT EXISTS public.quotes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content text NOT NULL,
    author text,
    category_id uuid REFERENCES public.motivation_categories(id) ON DELETE SET NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quotes_category
ON public.quotes(category_id);

-- 5. User quote preferences
CREATE TABLE IF NOT EXISTS public.user_quote_preferences (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_id uuid NOT NULL REFERENCES public.motivation_categories(id) ON DELETE CASCADE,
    prefers boolean NOT NULL DEFAULT true,
    is_favorite boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, category_id)
);

-- 6. Quote favorites
CREATE TABLE IF NOT EXISTS public.quote_favorites (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    quote_id uuid NOT NULL REFERENCES public.quotes(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, quote_id)
);

-- 7. Quote interactions
CREATE TABLE IF NOT EXISTS public.quote_interactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    quote_id uuid NOT NULL REFERENCES public.quotes(id) ON DELETE CASCADE,
    interaction_type text NOT NULL
        CHECK (interaction_type IN ('like', 'share', 'comment')),
    interaction_date date NOT NULL DEFAULT CURRENT_DATE,
    payload jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, quote_id, interaction_type, interaction_date)
);

CREATE INDEX IF NOT EXISTS idx_quote_interactions_user
ON public.quote_interactions(user_id);

CREATE INDEX IF NOT EXISTS idx_quote_interactions_quote
ON public.quote_interactions(quote_id);

-- 8. Goal categories
CREATE TABLE IF NOT EXISTS public.goal_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_goal_categories_global_name
ON public.goal_categories(lower(name))
WHERE user_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_goal_categories_user_name
ON public.goal_categories(user_id, lower(name))
WHERE user_id IS NOT NULL;

-- 9. Goals
CREATE TABLE IF NOT EXISTS public.goals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_id uuid REFERENCES public.goal_categories(id) ON DELETE SET NULL,
    title text NOT NULL,
    description text,
    reason text,
    start_date date NOT NULL DEFAULT CURRENT_DATE,
    target_date date,
    progress integer NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'completed', 'paused', 'cancelled')),
    is_completed boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (target_date IS NULL OR target_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_goals_user
ON public.goals(user_id);

-- 10. Tasks
CREATE TABLE IF NOT EXISTS public.tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    goal_id uuid REFERENCES public.goals(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    due_date date,
    is_done boolean NOT NULL DEFAULT false,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
    position integer NOT NULL DEFAULT 0,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (user_id IS NOT NULL OR goal_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_tasks_goal ON public.tasks(goal_id);
CREATE INDEX IF NOT EXISTS idx_tasks_user ON public.tasks(user_id);

-- 11. Task reminders
CREATE TABLE IF NOT EXISTS public.task_reminders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    remind_at timestamptz NOT NULL,
    message text,
    is_enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_reminders_task
ON public.task_reminders(task_id);

-- 12. Streaks
CREATE TABLE IF NOT EXISTS public.streaks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    streak_type text NOT NULL
        CHECK (streak_type IN (
            'app_usage',
            'task_completion',
            'motivation_interaction',
            'goal_achievement'
        )),
    current_streak integer NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
    longest_streak integer NOT NULL DEFAULT 0 CHECK (longest_streak >= 0),
    last_check_in date,
    tz text NOT NULL DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, streak_type)
);

-- 13. Achievements
CREATE TABLE IF NOT EXISTS public.achievements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    description text,
    icon_url text,
    points integer NOT NULL DEFAULT 0 CHECK (points >= 0),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 14. User achievements
CREATE TABLE IF NOT EXISTS public.user_achievements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    achievement_id uuid NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
    earned_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, achievement_id)
);

-- 15. Notification preferences
CREATE TABLE IF NOT EXISTS public.notification_preferences (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    push_enabled boolean NOT NULL DEFAULT true,
    email_enabled boolean NOT NULL DEFAULT true,
    motivation_enabled boolean NOT NULL DEFAULT true,
    task_reminders_enabled boolean NOT NULL DEFAULT true,
    notify_time time NOT NULL DEFAULT '09:00',
    timezone text NOT NULL DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- 16. Device tokens
CREATE TABLE IF NOT EXISTS public.device_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    token text NOT NULL,
    platform text NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, token)
);

-- 17. Custom themes
CREATE TABLE IF NOT EXISTS public.custom_themes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    name text NOT NULL,
    primary_color text NOT NULL DEFAULT '#FF922E',
    accent_color text DEFAULT '#FF7A00',
    background_color text DEFAULT '#101010',
    secondary_background_color text DEFAULT '#1B1B1B',
    text_color text DEFAULT '#FFFFFF',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, name),
    CHECK (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
    CHECK (accent_color IS NULL OR accent_color ~ '^#[0-9A-Fa-f]{6}$'),
    CHECK (background_color IS NULL OR background_color ~ '^#[0-9A-Fa-f]{6}$'),
    CHECK (secondary_background_color IS NULL OR secondary_background_color ~ '^#[0-9A-Fa-f]{6}$'),
    CHECK (text_color IS NULL OR text_color ~ '^#[0-9A-Fa-f]{6}$')
);

-- 18. User feedback
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    message text NOT NULL,
    rating integer CHECK (rating BETWEEN 1 AND 5),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 19. User ratings
CREATE TABLE IF NOT EXISTS public.user_ratings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
    reviewed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- 20. Admin roles
CREATE TABLE IF NOT EXISTS public.admin_roles (
    user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    role text NOT NULL DEFAULT 'admin'
        CHECK (role IN ('admin', 'super_admin')),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 21. Admin audit logs
CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    ip_address inet,
    occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_admin
ON public.admin_audit_logs(admin_user_id);

-- 22. Password reset tokens: store hashes only.
CREATE TABLE IF NOT EXISTS public.password_reset_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    used boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);
