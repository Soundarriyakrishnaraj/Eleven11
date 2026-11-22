
-- ============================================================
-- 007: Eleven11 Motivation Module
-- ============================================================

-- 1. Authors
CREATE TABLE IF NOT EXISTS public.authors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    bio text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Emotion tags
CREATE TABLE IF NOT EXISTS public.emotion_tags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- 3. Add author reference to existing quotes table
ALTER TABLE public.quotes
ADD COLUMN IF NOT EXISTS author_id uuid
REFERENCES public.authors(id) ON DELETE SET NULL;

-- 4. Quote-emotion relationships
CREATE TABLE IF NOT EXISTS public.quote_emotion_tags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_id uuid NOT NULL
        REFERENCES public.quotes(id) ON DELETE CASCADE,
    emotion_tag_id uuid NOT NULL
        REFERENCES public.emotion_tags(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (quote_id, emotion_tag_id)
);

-- 5. Daily quote assignments
CREATE TABLE IF NOT EXISTS public.daily_quote_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL
        REFERENCES public.profiles(id) ON DELETE CASCADE,
    quote_id uuid NOT NULL
        REFERENCES public.quotes(id) ON DELETE CASCADE,
    assigned_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, assigned_date)
);

-- 6. User-selected motivation categories
CREATE TABLE IF NOT EXISTS public.user_selected_categories (
    user_id uuid NOT NULL
        REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_id uuid NOT NULL
        REFERENCES public.motivation_categories(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, category_id)
);

-- 7. Indexes
CREATE INDEX IF NOT EXISTS idx_quote_emotion_tags_quote
ON public.quote_emotion_tags(quote_id);

CREATE INDEX IF NOT EXISTS idx_quote_emotion_tags_emotion
ON public.quote_emotion_tags(emotion_tag_id);

CREATE INDEX IF NOT EXISTS idx_daily_quote_user_date
ON public.daily_quote_assignments(user_id, assigned_date);

CREATE INDEX IF NOT EXISTS idx_user_selected_categories_user
ON public.user_selected_categories(user_id);

CREATE INDEX IF NOT EXISTS idx_quotes_author
ON public.quotes(author_id);

-- 8. Timestamp triggers
-- Only tables with updated_at use this trigger.

DROP TRIGGER IF EXISTS trg_authors_timestamp ON public.authors;

CREATE TRIGGER trg_authors_timestamp
BEFORE UPDATE ON public.authors
FOR EACH ROW
EXECUTE FUNCTION public.trigger_set_timestamp();

DROP TRIGGER IF EXISTS trg_emotion_tags_timestamp ON public.emotion_tags;

CREATE TRIGGER trg_emotion_tags_timestamp
BEFORE UPDATE ON public.emotion_tags
FOR EACH ROW
EXECUTE FUNCTION public.trigger_set_timestamp();

-- 9. Enable Row Level Security
ALTER TABLE public.authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emotion_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_emotion_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_quote_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_selected_categories ENABLE ROW LEVEL SECURITY;

-- 10. Remove policies if this migration is reapplied
DROP POLICY IF EXISTS authors_select ON public.authors;
DROP POLICY IF EXISTS authors_admin ON public.authors;

DROP POLICY IF EXISTS emotion_tags_select ON public.emotion_tags;
DROP POLICY IF EXISTS emotion_tags_admin ON public.emotion_tags;

DROP POLICY IF EXISTS quote_emotion_tags_select
ON public.quote_emotion_tags;

DROP POLICY IF EXISTS quote_emotion_tags_admin
ON public.quote_emotion_tags;

DROP POLICY IF EXISTS daily_quote_assignments_select
ON public.daily_quote_assignments;

DROP POLICY IF EXISTS user_selected_categories_select
ON public.user_selected_categories;

DROP POLICY IF EXISTS user_selected_categories_insert
ON public.user_selected_categories;

DROP POLICY IF EXISTS user_selected_categories_delete
ON public.user_selected_categories;

-- 11. Authors policies
CREATE POLICY authors_select
ON public.authors
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY authors_admin
ON public.authors
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 12. Emotion tag policies
CREATE POLICY emotion_tags_select
ON public.emotion_tags
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY emotion_tags_admin
ON public.emotion_tags
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 13. Quote-emotion relationship policies
-- Quote metadata is readable by authenticated users.
-- Only admins can modify global quote metadata.

CREATE POLICY quote_emotion_tags_select
ON public.quote_emotion_tags
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY quote_emotion_tags_admin
ON public.quote_emotion_tags
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 14. Daily quote assignment policies
-- Users can read only their own daily assignments.
-- Client-side writes are revoked below.

CREATE POLICY daily_quote_assignments_select
ON public.daily_quote_assignments
FOR SELECT
TO authenticated
USING (
    user_id = (SELECT auth.uid())
    OR public.is_admin()
);

-- 15. User-selected category policies
CREATE POLICY user_selected_categories_select
ON public.user_selected_categories
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

CREATE POLICY user_selected_categories_insert
ON public.user_selected_categories
FOR INSERT
TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY user_selected_categories_delete
ON public.user_selected_categories
FOR DELETE
TO authenticated
USING (user_id = (SELECT auth.uid()));

-- 16. Table privileges
REVOKE ALL ON TABLE
    public.authors,
    public.emotion_tags,
    public.quote_emotion_tags,
    public.daily_quote_assignments,
    public.user_selected_categories
FROM anon, authenticated;

GRANT SELECT ON TABLE
    public.authors,
    public.emotion_tags,
    public.quote_emotion_tags,
    public.daily_quote_assignments
TO authenticated;

GRANT INSERT, UPDATE, DELETE ON TABLE
    public.authors,
    public.emotion_tags,
    public.quote_emotion_tags
TO authenticated;

GRANT SELECT, INSERT, DELETE ON TABLE
    public.user_selected_categories
TO authenticated;

-- No client-side writes to server-managed daily assignments.
REVOKE INSERT, UPDATE, DELETE ON TABLE
    public.daily_quote_assignments
FROM anon, authenticated;

-- ============================================================
-- END OF MIGRATION 007
-- ============================================================
