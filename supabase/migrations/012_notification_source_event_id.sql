-- Add idempotency support to the existing notification history table.
-- Existing rows remain valid with a NULL source_event_id.
ALTER TABLE public.user_notifications
ADD COLUMN IF NOT EXISTS source_event_id text;

CREATE UNIQUE INDEX IF NOT EXISTS user_notifications_user_source_event_unique
ON public.user_notifications(user_id, source_event_id);
