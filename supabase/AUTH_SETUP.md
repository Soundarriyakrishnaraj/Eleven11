# Eleven11 authentication rollout

The migration and functions in this folder are generated but have not been
applied or deployed. Review and test them against a staging Supabase project
before applying them to production.

## Database rollout

1. Back up the project and inspect the live `public.profiles` schema and
   `handle_new_user` trigger.
2. Apply `migrations/011_username_auth_recovery.sql` to staging, then production
   only after review. It adds a nullable username, a case-insensitive unique
   index, server-only lookup functions, and rate-limit storage. It does not
   delete user/profile data or change existing RLS policies.
3. Keep the existing profiles RLS policies. New fields remain private to the
   profile owner under the current policy.

## Existing accounts

The migration deliberately leaves existing usernames and dates of birth null;
it does not guess usernames or modify profile data. Users who still have an
authenticated session can set a username and, if missing, date of birth in
Account Settings before signing out. A user with no username cannot use
username-only sign-in until they claim one. Plan a separate, verified claim
process for signed-out legacy users before making username-only sign-in the
only production login path.

## Edge Functions

Set a high-entropy server-only secret for HMAC-based rate-limit keys:

```powershell
supabase secrets set AUTH_RATE_LIMIT_SECRET="<random secret>"
```

Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. If the deployment does not
provide them automatically, configure them as server secrets. Never add the
service-role key to Flutter or commit it to source control.

After applying the migration, deploy:

```powershell
supabase functions deploy registration-check
supabase functions deploy username-login
supabase functions deploy password-recovery-start
```

These public entry points have `verify_jwt = false` because they are called
before login. They perform their own server-side validation and database-backed
rate limiting; the privileged database functions remain executable only by
`service_role`.

## Supabase Auth dashboard

- Configure a working SMTP sender for account recovery emails.
- Set the recovery email template to display the one-time token using
  `{{ .Token }}`. Keep the message generic; users enter this token in Eleven11.
- Set the recovery OTP expiry to 10 minutes (or another short interval). Supabase
  Auth validates and consumes the code; do not create a client-side token store.
- Keep Supabase Auth's built-in OTP verification limits enabled. The recovery
  start function also limits requests by IP and the submitted account details.
- Configure the password policy to require at least eight characters and enable
  leaked-password protection where available. Eleven11 additionally requires
  uppercase, lowercase, numeric, and symbol characters.
- The selected age rule is no minimum age. DOB is still required on new
  registration, and the existing database validation rejects future dates.
- Email confirmation may be disabled if immediate registration sign-in is
  required. If it remains enabled, new users must confirm their email before
  signing in; the app handles the no-session signup response.
- Retain the existing Google/provider settings if providers are added later;
  no Firebase Auth or Google Auth flow was found in the inspected app.

## Staging checks

Verify duplicate email and case-insensitive username handling, username sign-in
with valid and invalid credentials, account recovery with mismatched details,
expired/reused codes, rate limits, and password reset. Confirm that profile
reads remain owner-only and that unauthenticated clients cannot execute the
privileged lookup or rate-limit RPCs.
