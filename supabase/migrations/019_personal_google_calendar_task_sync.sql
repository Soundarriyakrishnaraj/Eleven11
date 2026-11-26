
-- =============================================================================
-- ELEVEN11 MIGRATION 019
-- Personal Google Calendar Task Synchronization
--
-- Purpose:
--   Per-user Google Calendar selection and synchronization preferences.
--   Task-to-Google-Calendar event mapping.
--
-- Run as: Supabase SQL Editor / postgres
--
-- Safety:
--   * Does not delete or overwrite existing task data.
--   * Does not modify existing RLS policies.
--   * Does not expose encrypted Google tokens to clients.
--   * Existing users are NOT automatically opted into task sync.
--   * Stops if the live schema differs from expectations.
--
-- DO NOT EXECUTE WITHOUT EXPLICIT APPROVAL.
-- =============================================================================

BEGIN;

SELECT pg_advisory_xact_lock(
    pg_catalog.hashtextextended('eleven11:migration:019', 0)
);

-- =============================================================================
-- 1. PREFLIGHT VALIDATION
-- =============================================================================

DO $preflight$
DECLARE
    v_type text;
    v_nullable text;
    v_rls boolean;
    v_column text;
BEGIN

    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION
          '[019] Run migration as postgres. Current user: %',
          current_user;
    END IF;

    IF to_regclass('public.tasks') IS NULL THEN
        RAISE EXCEPTION '[019] public.tasks does not exist.';
    END IF;

    IF to_regclass('public.user_google_calendar_tokens') IS NULL THEN
        RAISE EXCEPTION
          '[019] public.user_google_calendar_tokens does not exist.';
    END IF;

    -- Verify task ownership column.
    SELECT data_type, is_nullable
    INTO v_type, v_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'tasks'
      AND column_name = 'user_id';

    IF NOT FOUND OR v_type <> 'uuid' OR v_nullable <> 'NO' THEN
        RAISE EXCEPTION
          '[019] tasks.user_id must be UUID NOT NULL.';
    END IF;

    -- Verify token ownership column.
    SELECT data_type, is_nullable
    INTO v_type, v_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_google_calendar_tokens'
      AND column_name = 'user_id';

    IF NOT FOUND OR v_type <> 'uuid' OR v_nullable <> 'NO' THEN
        RAISE EXCEPTION
          '[019] user_google_calendar_tokens.user_id must be UUID NOT NULL.';
    END IF;

    -- Verify task identity and existing task date.
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'tasks'
          AND column_name = 'id'
    ) THEN
        RAISE EXCEPTION '[019] tasks.id is missing.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'tasks'
          AND column_name = 'due_date'
    ) THEN
        RAISE EXCEPTION
          '[019] tasks.due_date is missing. Inspect the task schema.';
    END IF;

    -- Verify RLS is enabled on both tables.
    SELECT relrowsecurity INTO v_rls
    FROM pg_class
    WHERE oid = 'public.tasks'::regclass;

    IF v_rls IS DISTINCT FROM true THEN
        RAISE EXCEPTION '[019] RLS is not enabled on public.tasks.';
    END IF;

    SELECT relrowsecurity INTO v_rls
    FROM pg_class
    WHERE oid = 'public.user_google_calendar_tokens'::regclass;

    IF v_rls IS DISTINCT FROM true THEN
        RAISE EXCEPTION
          '[019] RLS is not enabled on user_google_calendar_tokens.';
    END IF;

    -- Require existing user ownership policies for task operations.
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'tasks'
          AND cmd IN ('SELECT', 'ALL')
          AND roles && ARRAY['authenticated'::name, 'public'::name]
          AND position('auth.uid()' IN lower(coalesce(qual, ''))) > 0
          AND position('user_id' IN lower(coalesce(qual, ''))) > 0
    ) THEN
        RAISE EXCEPTION '[019] No authenticated task SELECT ownership policy found.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'tasks'
          AND cmd IN ('INSERT', 'ALL')
          AND roles && ARRAY['authenticated'::name, 'public'::name]
          AND position('auth.uid()' IN lower(coalesce(with_check, ''))) > 0
          AND position('user_id' IN lower(coalesce(with_check, ''))) > 0
    ) THEN
        RAISE EXCEPTION '[019] No authenticated task INSERT ownership policy found.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'tasks'
          AND cmd IN ('UPDATE', 'ALL')
          AND roles && ARRAY['authenticated'::name, 'public'::name]
          AND position('auth.uid()' IN lower(coalesce(qual, ''))) > 0
          AND position('user_id' IN lower(coalesce(qual, ''))) > 0
          AND position('auth.uid()' IN lower(coalesce(with_check, ''))) > 0
          AND position('user_id' IN lower(coalesce(with_check, ''))) > 0
    ) THEN
        RAISE EXCEPTION '[019] No authenticated task UPDATE ownership policy found.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'tasks'
          AND cmd IN ('DELETE', 'ALL')
          AND roles && ARRAY['authenticated'::name, 'public'::name]
          AND position('auth.uid()' IN lower(coalesce(qual, ''))) > 0
          AND position('user_id' IN lower(coalesce(qual, ''))) > 0
    ) THEN
        RAISE EXCEPTION '[019] No authenticated task DELETE ownership policy found.';
    END IF;

    -- Refuse partial or previously applied installations.
    FOREACH v_column IN ARRAY ARRAY[
        'selected_calendar_id',
        'selected_calendar_name',
        'auto_task_sync',
        'default_reminder_minutes'
    ]
    LOOP
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'user_google_calendar_tokens'
              AND column_name = v_column
        ) THEN
            RAISE EXCEPTION
              '[019] Column user_google_calendar_tokens.% already exists. Inspect partial state.',
              v_column;
        END IF;
    END LOOP;

    FOREACH v_column IN ARRAY ARRAY[
        'due_time',
        'end_time',
        'timezone',
        'reminder_minutes',
        'google_calendar_id',
        'google_event_id',
        'google_sync_status'
    ]
    LOOP
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'tasks'
              AND column_name = v_column
        ) THEN
            RAISE EXCEPTION
              '[019] Column tasks.% already exists. Inspect partial state.',
              v_column;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'idx_tasks_user_google_event_unique'
    ) THEN
        RAISE EXCEPTION
          '[019] Index idx_tasks_user_google_event_unique already exists.';
    END IF;

END;
$preflight$;

-- =============================================================================
-- 2. PER-USER GOOGLE CALENDAR SETTINGS
-- =============================================================================

ALTER TABLE public.user_google_calendar_tokens
    ADD COLUMN selected_calendar_id text NOT NULL DEFAULT 'primary',
    ADD COLUMN selected_calendar_name text,
    ADD COLUMN auto_task_sync boolean NOT NULL DEFAULT false,
    ADD COLUMN default_reminder_minutes integer NOT NULL DEFAULT 15;

ALTER TABLE public.user_google_calendar_tokens
    ADD CONSTRAINT tokens_default_reminder_nonnegative_019
        CHECK (default_reminder_minutes >= 0),
    ADD CONSTRAINT tokens_calendar_id_nonempty_019
        CHECK (length(btrim(selected_calendar_id)) > 0);

-- IMPORTANT:
-- These preferences are managed by the authenticated Node.js backend.
-- Do not add direct client access to encrypted Google token records.
-- Preserve existing RLS and grants.

-- =============================================================================
-- 3. EXTEND TASKS
-- =============================================================================

ALTER TABLE public.tasks
    ADD COLUMN due_time text,
    ADD COLUMN end_time text,
    ADD COLUMN timezone text NOT NULL DEFAULT 'Asia/Kolkata',
    ADD COLUMN reminder_minutes integer,
    ADD COLUMN google_calendar_id text,
    ADD COLUMN google_event_id text,
    ADD COLUMN google_sync_status text NOT NULL DEFAULT 'none';

-- =============================================================================
-- 4. TASK DATA VALIDATION
-- =============================================================================

ALTER TABLE public.tasks
    ADD CONSTRAINT tasks_due_time_format_019
      CHECK (
        due_time IS NULL OR
        due_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$'
      ),

    ADD CONSTRAINT tasks_end_time_format_019
      CHECK (
        end_time IS NULL OR
        end_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$'
      ),

    ADD CONSTRAINT tasks_timezone_nonempty_019
      CHECK (length(btrim(timezone)) > 0),

    ADD CONSTRAINT tasks_reminder_nonnegative_019
      CHECK (reminder_minutes IS NULL OR reminder_minutes >= 0),

    ADD CONSTRAINT tasks_sync_status_check_019
      CHECK (
        google_sync_status IN (
          'none',
          'pending',
          'synced',
          'failed'
        )
      ),

    ADD CONSTRAINT tasks_google_calendar_id_nonempty_019
      CHECK (
        google_calendar_id IS NULL OR
        length(btrim(google_calendar_id)) > 0
      ),

    ADD CONSTRAINT tasks_google_event_id_nonempty_019
      CHECK (
        google_event_id IS NULL OR
        length(btrim(google_event_id)) > 0
      ),

    ADD CONSTRAINT tasks_google_event_mapping_019
      CHECK (
        google_event_id IS NULL
        OR google_calendar_id IS NOT NULL
      ),

    ADD CONSTRAINT tasks_synced_event_mapping_019
      CHECK (
        google_sync_status <> 'synced'
        OR (
          google_event_id IS NOT NULL
          AND google_calendar_id IS NOT NULL
        )
      );

-- =============================================================================
-- 5. UNIQUE EVENT MAPPING PER USER AND CALENDAR
-- =============================================================================

CREATE UNIQUE INDEX idx_tasks_user_google_event_unique
    ON public.tasks (
        user_id,
        google_calendar_id,
        google_event_id
    )
    WHERE google_event_id IS NOT NULL;

-- =============================================================================
-- 6. DOCUMENT THE NEW COLUMNS
-- =============================================================================

COMMENT ON COLUMN public.user_google_calendar_tokens.selected_calendar_id
    IS 'Google Calendar ID selected by this Eleven11 user.';

COMMENT ON COLUMN public.user_google_calendar_tokens.auto_task_sync
    IS 'Explicit user preference for automatic task synchronization. Defaults OFF.';

COMMENT ON COLUMN public.tasks.google_calendar_id
    IS 'Google Calendar containing this task event.';

COMMENT ON COLUMN public.tasks.google_event_id
    IS 'Google Calendar event ID mapped to this Eleven11 task.';

COMMENT ON COLUMN public.tasks.google_sync_status
    IS 'Task synchronization state: none, pending, synced, failed.';

COMMENT ON COLUMN public.tasks.timezone
    IS 'IANA timezone for task event scheduling.';

COMMIT;

-- =============================================================================
-- END MIGRATION 019
-- =============================================================================
