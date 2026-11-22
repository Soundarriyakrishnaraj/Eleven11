CREATE TABLE IF NOT EXISTS public.user_onboarding (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    answers JSONB NOT NULL DEFAULT '{}'::jsonb,
    notification_time TIME NOT NULL DEFAULT '09:00:00',
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_onboarding ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own onboarding"
ON public.user_onboarding;

CREATE POLICY "Users can view own onboarding"
ON public.user_onboarding
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own onboarding"
ON public.user_onboarding;

CREATE POLICY "Users can insert own onboarding"
ON public.user_onboarding
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own onboarding"
ON public.user_onboarding;

CREATE POLICY "Users can update own onboarding"
ON public.user_onboarding
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE
ON public.user_onboarding TO authenticated;