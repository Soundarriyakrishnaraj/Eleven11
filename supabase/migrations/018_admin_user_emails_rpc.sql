-- Migration 018: Admin RPC to fetch user emails from auth.users in Direct DB mode
CREATE OR REPLACE FUNCTION public.get_admin_users_emails(user_ids uuid[])
RETURNS TABLE(id uuid, email text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF auth.uid() <> '74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a'::uuid
     AND NOT EXISTS (
       SELECT 1 FROM public.admin_roles
       WHERE user_id = auth.uid() AND role IN ('admin', 'super_admin')
     ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  SELECT u.id, u.email::text
  FROM auth.users u
  WHERE u.id = ANY(user_ids);
END;
$$;

REVOKE ALL ON FUNCTION public.get_admin_users_emails(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_users_emails(uuid[]) TO authenticated;
