-- ============================================================================
-- Migration 015: Events and Google Calendar Integration
-- Target: PostgreSQL / Supabase
-- Safety: Non-destructive. Strict absence assertions. Transactional via Supabase CLI.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PRE-MIGRATION STRUCTURAL SAFETY ASSERTION
-- ----------------------------------------------------------------------------
-- Fails immediately if ANY of the three tables already unexpectedly exist in public schema.
-- Prevents accidental schema contamination or partial overwrites.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'events'
    ) THEN
        RAISE EXCEPTION 'SAFETY HALT: Table public.events already exists. Manual inspection required before applying migration 015.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'user_google_calendar_tokens'
    ) THEN
        RAISE EXCEPTION 'SAFETY HALT: Table public.user_google_calendar_tokens already exists.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'google_oauth_states'
    ) THEN
        RAISE EXCEPTION 'SAFETY HALT: Table public.google_oauth_states already exists.';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- ROLLBACK AND DISASTER RECOVERY POLICY
-- ----------------------------------------------------------------------------
-- CAUTION:
--   Dropping tables permanently deletes all stored records and forces users to re-authorize.
--   Do NOT use CASCADE so external tables can never be inadvertently dropped.
--
-- BEFORE APPLYING IN PRODUCTION:
--   - Perform a full database backup (via Supabase project dashboard or pg_dump).
--
-- SAFE ROLLBACK PROCEDURES:
-- A. Rollback BEFORE any production event data exists (Clean Uninstallation):
--      DROP TABLE IF EXISTS public.google_oauth_states;
--      DROP TABLE IF EXISTS public.user_google_calendar_tokens;
--      DROP TABLE IF EXISTS public.events;
--
-- B. Rollback AFTER production data exists (Preserve Eleven11 Data, Detach Google):
--      -- Cleanly unlinks Google Calendar while retaining 100% of user events,
--      -- meeting notes, attendee lists, and reminders in Eleven11:
--      UPDATE public.events 
--      SET sync_with_google = false, 
--          google_event_id = NULL, 
--          google_html_link = NULL, 
--          google_etag = NULL,
--          google_recurring_event_id = NULL,
--          original_start_time = NULL,
--          original_start_timezone = NULL,
--          sync_status = 'synced',
--          sync_lease_until = NULL,
--          sync_lease_owner = NULL;
--      -- Safely remove credentials and OAuth state tables:
--      DROP TABLE IF EXISTS public.google_oauth_states;
--      DROP TABLE IF EXISTS public.user_google_calendar_tokens;
-- ----------------------------------------------------------------------------

-- ============================================================================
-- 2. Events Table (Separated sync_status, lease tokens, and recurring support)
-- ============================================================================
CREATE TABLE public.events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title text NOT NULL DEFAULT '',
    description text,
    location text,
    start_time timestamptz NOT NULL,
    end_time timestamptz NOT NULL,
    timezone text NOT NULL DEFAULT 'UTC',
    is_all_day boolean NOT NULL DEFAULT false,
    
    -- Google Calendar integration mapping
    sync_with_google boolean NOT NULL DEFAULT false,
    google_event_id text,
    google_html_link text,
    google_etag text,
    
    -- Recurring event fields (Option A: Master + Exception Model)
    recurrence_rules text[],                 -- Populated on Series Master (e.g. ['RRULE:FREQ=WEEKLY;BYDAY=MO'])
    google_recurring_event_id text,          -- Populated ONLY on Exception instances (pointing to master google_event_id)
    original_start_time timestamptz,         -- Original start time of this exception instance
    original_start_timezone text,            -- Timezone of original exception instance
    
    reminder_minutes integer DEFAULT 15 CHECK (reminder_minutes >= 0),
    attendees jsonb DEFAULT '[]'::jsonb,
    
    -- Event Domain Status (Standard RFC 5545 / Google Calendar statuses)
    status text NOT NULL DEFAULT 'confirmed' 
        CHECK (status IN ('confirmed', 'tentative', 'cancelled')),

    -- Synchronization Lifecycle Status
    sync_status text NOT NULL DEFAULT 'synced'
        CHECK (sync_status IN ('pending', 'syncing', 'synced', 'failed')),
    
    -- Distributed Concurrency Lease & Idempotency
    idempotency_key text,
    sync_lease_until timestamptz,
    sync_lease_owner text,
    
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- Validation: End time must be on or after start time
    CONSTRAINT events_end_on_or_after_start CHECK (end_time >= start_time),

    -- Durable Idempotency Constraint per User
    CONSTRAINT events_user_idempotency_key UNIQUE (user_id, idempotency_key)
);

-- Compound Unique Partial Index enforcing tenant isolation and unique Google mapping per user
CREATE UNIQUE INDEX idx_events_user_google_id
ON public.events(user_id, google_event_id)
WHERE google_event_id IS NOT NULL;

CREATE INDEX idx_events_user_start
ON public.events(user_id, start_time);

CREATE INDEX idx_events_recurring_parent
ON public.events(user_id, google_recurring_event_id)
WHERE google_recurring_event_id IS NOT NULL;

CREATE INDEX idx_events_sync_lease
ON public.events(user_id, sync_status, sync_lease_until)
WHERE sync_status = 'syncing';

-- Enable RLS
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- Verified Isolation Policies (Scoped by auth.uid() = user_id)
CREATE POLICY "events_user_isolation_select"
    ON public.events FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "events_user_isolation_insert"
    ON public.events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "events_user_isolation_update"
    ON public.events FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "events_user_isolation_delete"
    ON public.events FOR DELETE
    USING (auth.uid() = user_id);


-- ============================================================================
-- 3. Encrypted Google Calendar Token Storage
-- ============================================================================
-- Stores AES-256-GCM encrypted tokens.
-- Zero client policies: Strictly accessed by backend service role or pooler.
CREATE TABLE public.user_google_calendar_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    google_email text,
    encrypted_access_token text NOT NULL,
    encrypted_refresh_token text NOT NULL,
    token_expires_at timestamptz NOT NULL,
    scope text NOT NULL,
    next_sync_token text,
    last_synced_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_google_tokens_user
ON public.user_google_calendar_tokens(user_id);

ALTER TABLE public.user_google_calendar_tokens ENABLE ROW LEVEL SECURITY;
-- Default deny: No client RLS policies for anon or authenticated roles.


-- ============================================================================
-- 4. Ephemeral OAuth States with Encrypted PKCE Verifiers
-- ============================================================================
CREATE TABLE public.google_oauth_states (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    state_token text NOT NULL UNIQUE,
    encrypted_code_verifier text NOT NULL,
    expires_at timestamptz NOT NULL,
    is_used boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_google_oauth_states_lookup
ON public.google_oauth_states(state_token, is_used, expires_at);

ALTER TABLE public.google_oauth_states ENABLE ROW LEVEL SECURITY;
-- Default deny: No client RLS policies for anon or authenticated roles.
