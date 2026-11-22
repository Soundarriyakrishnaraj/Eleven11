-- 001_create_tables.sql
-- Supabase PostgreSQL migrations for Eleven11 backend foundation
-- Run with supabase db push or via SQL migration tool.

-- Enable uuid-ossp extension for UUID generation
create extension if not exists "uuid-ossp";

-- 1. profiles (extends auth.users)
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text,
    avatar_url text,
    date_of_birth date,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    deleted_at timestamp with time zone,
    constraint ck_date_of_birth_past check (date_of_birth < now())
);
create index if not exists idx_profiles_full_name on public.profiles (full_name);

-- 2. onboarding_responses
create table if not exists public.onboarding_responses (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    question_key text not null,
    answer jsonb not null,
    created_at timestamp with time zone default now()
);
create index if not exists idx_onboarding_user on public.onboarding_responses (user_id);

-- 3. motivation_categories (public reference data)
create table if not exists public.motivation_categories (
    id uuid primary key default uuid_generate_v4(),
    name text not null unique,
    description text,
    is_active boolean default true,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

-- 4. quotes
create table if not exists public.quotes (
    id uuid primary key default uuid_generate_v4(),
    content text not null,
    author text,
    category_id uuid references public.motivation_categories(id) on delete set null,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
create index if not exists idx_quotes_category on public.quotes (category_id);

-- 5. user_quote_preferences (per‑user preferences for categories)
create table if not exists public.user_quote_preferences (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    category_id uuid references public.motivation_categories(id) on delete cascade,
    is_favorite boolean default false,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    unique (user_id, category_id)
);

-- 6. favorite_quotes (many‑to‑many user → quote)
create table if not exists public.favorite_quotes (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    quote_id uuid references public.quotes(id) on delete cascade,
    created_at timestamp with time zone default now(),
    unique (user_id, quote_id)
);

-- 7. quote_interactions (likes, shares, etc.)
create table if not exists public.quote_interactions (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    quote_id uuid references public.quotes(id) on delete cascade,
    interaction_type text check (interaction_type in ('like','share','comment')),
    payload jsonb,
    created_at timestamp with time zone default now()
);
create index if not exists idx_quote_interactions_user on public.quote_interactions (user_id);
create index if not exists idx_quote_interactions_quote on public.quote_interactions (quote_id);

-- 8. goals
create table if not exists public.goals (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    title text not null,
    description text,
    target_date date,
    is_completed boolean default false,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
create index if not exists idx_goals_user on public.goals (user_id);

-- 9. goal_categories (reference data for goal taxonomy)
create table if not exists public.goal_categories (
    id uuid primary key default uuid_generate_v4(),
    name text not null unique,
    created_at timestamp with time zone default now()
);

-- 10. tasks (belong to a goal)
create table if not exists public.tasks (
    id uuid primary key default uuid_generate_v4(),
    goal_id uuid references public.goals(id) on delete cascade,
    title text not null,
    description text,
    due_date date,
    is_done boolean default false,
    position integer,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
create index if not exists idx_tasks_goal on public.tasks (goal_id);

-- 11. task_reminders
create table if not exists public.task_reminders (
    id uuid primary key default uuid_generate_v4(),
    task_id uuid references public.tasks(id) on delete cascade,
    remind_at timestamp with time zone not null,
    created_at timestamp with time zone default now()
);
create index if not exists idx_task_reminders_task on public.task_reminders (task_id);

-- 12. streaks (daily streak tracking per user)
create table if not exists public.streaks (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    current_streak integer default 0,
    longest_streak integer default 0,
    last_check_in date,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
create index if not exists idx_streaks_user on public.streaks (user_id);

-- 13. achievements (catalog of possible achievements)
create table if not exists public.achievements (
    id uuid primary key default uuid_generate_v4(),
    name text not null unique,
    description text,
    icon_url text,
    points integer default 0,
    created_at timestamp with time zone default now()
);

-- 14. user_achievements (earned achievements)
create table if not exists public.user_achievements (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    achievement_id uuid references public.achievements(id) on delete cascade,
    earned_at timestamp with time zone default now(),
    unique (user_id, achievement_id)
);
create index if not exists idx_user_achievements_user on public.user_achievements (user_id);

-- 15. notification_preferences (per‑user settings)
create table if not exists public.notification_preferences (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    push_enabled boolean default true,
    email_enabled boolean default true,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

-- 16. device_tokens (push notification tokens)
create table if not exists public.device_tokens (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    token text not null,
    platform text check (platform in ('android','ios','web')),
    created_at timestamp with time zone default now(),
    unique (user_id, token)
);

-- 17. custom_themes (user‑defined UI themes)
create table if not exists public.custom_themes (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    name text not null,
    primary_color text,
    accent_color text,
    background_color text,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    unique (user_id, name)
);

-- 18. user_feedback (in‑app feedback messages)
create table if not exists public.user_feedback (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    message text not null,
    rating integer check (rating between 1 and 5),
    created_at timestamp with time zone default now()
);

-- 19. user_ratings (optional separate rating entity)
create table if not exists public.user_ratings (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    rating integer check (rating between 1 and 5) not null,
    reviewed_at timestamp with time zone default now(),
    unique (user_id)
);

-- 20. admin_audit_logs (security‑critical audit trail)
create table if not exists public.admin_audit_logs (
    id uuid primary key default uuid_generate_v4(),
    admin_user_id uuid references public.profiles(id) on delete set null,
    action text not null,
    details jsonb,
    ip_address inet,
    occurred_at timestamp with time zone default now()
);
create index if not exists idx_audit_admin on public.admin_audit_logs (admin_user_id);

-- Password reset tokens table (secure token storage)
create table if not exists public.password_reset_tokens (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade,
    token_hash text not null,
    expires_at timestamp with time zone not null,
    used boolean default false,
    created_at timestamp with time zone default now(),
    unique (token_hash)
);

-- Enable Row Level Security on all tables that contain user data
do $$
    declare r record;
begin
    for r in
        select tablename from pg_tables where schemaname = 'public' and tablename not in ('motivation_categories','goal_categories','achievements')
    loop
        execute format('alter table public.%I enable row level security', r.tablename);
    end loop;
end $$;

-- End of migration