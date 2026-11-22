-- ============================================================
-- 010: Eleven11 Premium Notification Centre
-- ============================================================

-- 1. Create user_notifications table for storing notification history
CREATE TABLE IF NOT EXISTS public.user_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type text NOT NULL CHECK (type IN (
        'alarm',
        'task',
        'goal',
        'motivation',
        'announcement',
        'general',
        'reminder',
        'update'
    )),
    title text NOT NULL,
    body text NOT NULL,
    data jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_read boolean NOT NULL DEFAULT false,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Performance indexes
CREATE INDEX IF NOT EXISTS idx_user_notifications_user_date
ON public.user_notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_notifications_unread
ON public.user_notifications(user_id, is_read)
WHERE is_read = false;

CREATE INDEX IF NOT EXISTS idx_user_notifications_type
ON public.user_notifications(user_id, type);

-- 3. Automatic timestamp trigger
DROP TRIGGER IF EXISTS trg_user_notifications_timestamp ON public.user_notifications;

CREATE TRIGGER trg_user_notifications_timestamp
BEFORE UPDATE ON public.user_notifications
FOR EACH ROW
EXECUTE FUNCTION public.trigger_set_timestamp();

-- 4. Enable Row Level Security
ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_notifications_select" ON public.user_notifications;
CREATE POLICY "user_notifications_select"
ON public.user_notifications
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_notifications_insert" ON public.user_notifications;
CREATE POLICY "user_notifications_insert"
ON public.user_notifications
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_notifications_update" ON public.user_notifications;
CREATE POLICY "user_notifications_update"
ON public.user_notifications
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_notifications_delete" ON public.user_notifications;
CREATE POLICY "user_notifications_delete"
ON public.user_notifications
FOR DELETE TO authenticated
USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.user_notifications TO authenticated;

-- 5. Extend notification_preferences table for full feature toggles
ALTER TABLE public.notification_preferences
ADD COLUMN IF NOT EXISTS alarm_notifications_enabled boolean NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS goal_reminders_enabled boolean NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS announcements_enabled boolean NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS sound_enabled boolean NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS vibration_enabled boolean NOT NULL DEFAULT true;

-- 6. Ensure user_device_tokens compatibility table exists for FCM
CREATE TABLE IF NOT EXISTS public.user_device_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    fcm_token text NOT NULL UNIQUE,
    platform text NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user
ON public.user_device_tokens(user_id);

ALTER TABLE public.user_device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_device_tokens_select" ON public.user_device_tokens;
CREATE POLICY "user_device_tokens_select"
ON public.user_device_tokens
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_device_tokens_insert" ON public.user_device_tokens;
CREATE POLICY "user_device_tokens_insert"
ON public.user_device_tokens
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_device_tokens_update" ON public.user_device_tokens;
CREATE POLICY "user_device_tokens_update"
ON public.user_device_tokens
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_device_tokens_delete" ON public.user_device_tokens;
CREATE POLICY "user_device_tokens_delete"
ON public.user_device_tokens
FOR DELETE TO authenticated
USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.user_device_tokens TO authenticated;
