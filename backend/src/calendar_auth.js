
function calendarBearerToken(request) {
  const authorization = request.get('authorization') ?? '';
  const match = /^Bearer\s+([A-Za-z0-9._-]+)$/.exec(authorization);
  return match?.[1] ?? null;
}

export function createRequireCalendarAuth({
  admin,
  findSession,
  pgPool,
  requestError,
}) {
  if (typeof findSession !== 'function') {
    throw new TypeError(
      'createRequireCalendarAuth requires findSession.',
    );
  }

  return async function requireCalendarAuth(request, response) {
    const token = calendarBearerToken(request);

    if (!token) {
      requestError(response, 401, 'Authentication required.');
      return null;
    }

    // Supabase JWT authentication.
    if (token.includes('.')) {
      if (typeof admin?.auth?.getUser !== 'function') {
        requestError(
          response,
          503,
          'Authentication service temporarily unavailable.',
        );
        return null;
      }

      let result;

      try {
        result = await admin.auth.getUser(token);
      } catch {
        requestError(
          response,
          503,
          'Authentication service temporarily unavailable.',
        );
        return null;
      }

      if (result?.error) {
        requestError(
          response,
          401,
          'Your session has expired. Please sign in.',
        );
        return null;
      }

      const userId = result?.data?.user?.id;

      if (!userId) {
        requestError(
          response,
          401,
          'Your session has expired. Please sign in.',
        );
        return null;
      }

      return {
        userId,
        authType: 'supabase_jwt',
      };
    }

    // Legacy opaque-session authentication.
    let session;

    try {
      session = await findSession(token);
    } catch {
      requestError(
        response,
        503,
        'Authentication service temporarily unavailable.',
      );
      return null;
    }

    if (!session?.userId) {
      requestError(response, 401, 'Invalid or expired session.');
      return null;
    }

    try {
      let profileExists = false;

      if (pgPool?.query) {
        const profileResult = await pgPool.query(
          'SELECT id FROM public.profiles WHERE id = $1 LIMIT 1',
          [session.userId],
        );

        profileExists = profileResult.rows.length > 0;
      } else {
        if (typeof admin?.from !== 'function') {
          requestError(
            response,
            503,
            'Authentication service temporarily unavailable.',
          );
          return null;
        }

        const { data, error } = await admin
          .from('profiles')
          .select('id')
          .eq('id', session.userId)
          .maybeSingle();

        if (error) {
          requestError(
            response,
            503,
            'Authentication service temporarily unavailable.',
          );
          return null;
        }

        profileExists = Boolean(data?.id);
      }

      if (!profileExists) {
        requestError(
          response,
          401,
          'User profile not found for this session.',
        );
        return null;
      }

      return {
        userId: session.userId,
        authType: 'legacy_session',
      };
    } catch {
      requestError(
        response,
        503,
        'Authentication service temporarily unavailable.',
      );
      return null;
    }
  };
}
