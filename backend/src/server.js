
import { randomBytes, randomUUID } from 'node:crypto';
import express from 'express';
import pg from 'pg';
import { createClient } from '@supabase/supabase-js';
import {
  constantTimeHexEqual,
  hashPassword,
  hmacHex,
  newOpaqueToken,
  normalizeEmail,
  normalizeUsername,
  parseAndValidateEncryptionKey,
  passwordsMatch,
  sha256Hex,
  signDatabaseJwt,
  validDateOfBirth,
  validEmail,
  validatePassword,
  validUsername,
  verifyPassword,
} from './security.js';
import { createRequireCalendarAuth } from './calendar_auth.js';
import { createAdminHandlers } from './admin_api.js';

import {
  deleteEventFromGoogle,
  disconnectCalendar,
  getAuthUrl,
  getCalendarStatus,
  handleOAuthCallback,
  pullSyncGoogleCalendar,
  pushEventToGoogle,
} from './google_calendar.js';

const SESSION_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000;
const RESET_TOKEN_LIFETIME_MS = 10 * 60 * 1000;

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function createConfig() {
  const rateSecret = requiredEnv('AUTH_RATE_LIMIT_SECRET');
  const jwtSecret = requiredEnv('SUPABASE_JWT_SECRET');

  if (Buffer.byteLength(rateSecret) < 32) {
    throw new Error('AUTH_RATE_LIMIT_SECRET must be at least 32 bytes.');
  }

  if (Buffer.byteLength(jwtSecret) < 32) {
    throw new Error('SUPABASE_JWT_SECRET must be at least 32 bytes.');
  }

  const googleClientId = process.env.GOOGLE_CLIENT_ID?.trim() || '';
  const googleClientSecret = process.env.GOOGLE_CLIENT_SECRET?.trim() || '';
  const googleRedirectUri = process.env.GOOGLE_REDIRECT_URI?.trim() || '';
  const encKeyHex = process.env.GOOGLE_CALENDAR_ENCRYPTION_KEY?.trim() || '';

  const encryptionKey = encKeyHex
    ? parseAndValidateEncryptionKey(encKeyHex)
    : null;

  return {
    port: Number(process.env.PORT ?? '3000'),
    databaseUrl: process.env.DATABASE_URL?.trim(),
    supabaseUrl: requiredEnv('SUPABASE_URL').replace(/\/+$/, ''),
    supabaseAnonKey: requiredEnv('SUPABASE_ANON_KEY'),
    serviceRoleKey: requiredEnv('SUPABASE_SERVICE_ROLE_KEY'),
    jwtSecret,
    rateSecret,
    googleClientId,
    googleClientSecret,
    googleRedirectUri,
    encryptionKey,
    trustProxy: process.env.TRUST_PROXY === 'true',
    allowedOrigins: new Set(
      (process.env.ALLOWED_ORIGINS ?? '')
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean),
    ),
  };
}

const config = createConfig();

// PostgreSQL client via Supabase Session Pooler
export const pgPool = config.databaseUrl
  ? new pg.Pool({
    connectionString: config.databaseUrl,
    max: 10,
    idleTimeoutMillis: 30000,
    ssl: { rejectUnauthorized: false },
  })
  : null;

// Supabase Admin client
export const admin = createClient(
  config.supabaseUrl,
  config.serviceRoleKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  },
);

export const app = express();

app.disable('x-powered-by');
app.set('trust proxy', config.trustProxy ? 1 : false);

// -----------------------------------------------------------------------------
// CORS AND PREFLIGHT
// -----------------------------------------------------------------------------

app.use((request, response, next) => {
  const origin = request.get('origin');

  if (origin && config.allowedOrigins.has(origin)) {
    response.setHeader('Access-Control-Allow-Origin', origin);
    response.setHeader('Vary', 'Origin');
  } else if (origin && config.allowedOrigins.size > 0) {
    return response.status(403).json({ error: 'Origin not allowed.' });
  }

  response.setHeader(
    'Access-Control-Allow-Headers',
    'authorization, apikey, x-client-info, content-type, prefer, range, accept-profile, content-profile',
  );

  response.setHeader(
    'Access-Control-Allow-Methods',
    'GET, POST, PATCH, PUT, DELETE, OPTIONS',
  );

  response.setHeader(
    'Access-Control-Expose-Headers',
    'content-range, range-unit, preference-applied, location, content-location',
  );

  if (request.method === 'OPTIONS') {
    return response.sendStatus(204);
  }

  next();
});

app.get('/healthz', async (_request, response) => {
  if (!pgPool) {
    return response.status(503).json({
      status: 'degraded',
      pooler: false,
      database: 'not_configured',
    });
  }

  try {
    await pgPool.query('SELECT 1');
    return response.status(200).json({
      status: 'ok',
      pooler: true,
      database: 'connected',
    });
  } catch (error) {
    console.error('Database health check failed:', error?.message || 'Unknown error');
    return response.status(503).json({
      status: 'degraded',
      pooler: true,
      database: 'unavailable',
    });
  }
});

function requestError(response, status, message) {
  return response.status(status).json({ error: message });
}

function bearerToken(request) {
  const authorization = request.get('authorization') ?? '';
  const match = /^Bearer ([A-Za-z0-9_-]{40,100})$/.exec(authorization);
  return match?.[1] ?? null;
}

// -----------------------------------------------------------------------------
// RATE LIMITING
// -----------------------------------------------------------------------------

async function rateLimitPasses(
  request,
  scope,
  subject,
  limit,
  windowSeconds,
) {
  const ip = request.ip || request.socket?.remoteAddress || 'unknown';
  const keys = [`ip:${ip}`, `subject:${subject}`];

  for (const key of keys) {
    const keyHash = hmacHex(config.rateSecret, `${scope}:${key}`);

    const { data, error } = await admin.rpc('consume_auth_rate_limit', {
      p_scope: scope,
      p_key_hash: keyHash,
      p_limit: limit,
      p_window_seconds: windowSeconds,
    });

    if (error) {
      console.error('Rate limit check error:', error);
      return false;
    }

    if (data !== true) return false;
  }

  return true;
}

// -----------------------------------------------------------------------------
// SESSION VALIDATION
// -----------------------------------------------------------------------------

async function findSession(token) {
  if (!token) return null;

  const tokenHash = sha256Hex(token);

  if (pgPool) {
    const result = await pgPool.query(
      `SELECT id, account_id, expires_at, is_revoked
       FROM public.user_sessions
       WHERE token_hash = $1`,
      [tokenHash],
    );

    const row = result.rows[0];

    if (
      !row ||
      row.is_revoked ||
      new Date(row.expires_at) <= new Date()
    ) {
      return null;
    }

    return {
      id: row.id,
      userId: row.account_id,
      expiresAt: row.expires_at,
    };
  }

  const { data, error } = await admin
    .from('user_sessions')
    .select('id, account_id, expires_at, is_revoked')
    .eq('token_hash', tokenHash)
    .maybeSingle();

  if (
    error ||
    !data ||
    data.is_revoked ||
    Date.parse(data.expires_at) <= Date.now()
  ) {
    return null;
  }

  return {
    id: data.id,
    userId: data.account_id,
    expiresAt: data.expires_at,
  };
}

async function requireSession(request, response) {
  try {
    const session = await findSession(bearerToken(request));

    if (!session) {
      requestError(
        response,
        401,
        'Your session has expired. Please sign in.',
      );
      return null;
    }

    return session;
  } catch (error) {
    console.error('Session validation failed.', error);

    requestError(
      response,
      503,
      'Unable to validate your session.',
    );

    return null;
  }
}

async function loadAccount(userId) {
  if (pgPool) {
    const result = await pgPool.query(
      `SELECT a.id, a.username, a.email, a.dob, p.full_name
       FROM public.user_accounts a
       LEFT JOIN public.profiles p ON p.id = a.id
       WHERE a.id = $1`,
      [userId],
    );

    const row = result.rows[0];

    if (!row) return null;

    return {
      id: row.id,
      username: row.username,
      email: row.email,
      dob: row.dob,
      fullName: row.full_name ?? row.username ?? '',
    };
  }

  const { data, error } = await admin
    .from('user_accounts')
    .select('id, username, email, dob')
    .eq('id', userId)
    .maybeSingle();

  if (error || !data) return null;

  const { data: profile } = await admin
    .from('profiles')
    .select('full_name')
    .eq('id', userId)
    .maybeSingle();

  return {
    id: data.id,
    username: data.username,
    email: data.email,
    dob: data.dob,
    fullName: profile?.full_name ?? data.username ?? '',
  };
}

// -----------------------------------------------------------------------------
// POSTGREST DATABASE PROXY
// -----------------------------------------------------------------------------

app.use(
  '/rest/v1',
  express.raw({
    type: '*/*',
    limit: '5mb',
  }),
  async (request, response) => {
    if (
      !['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'HEAD'].includes(
        request.method,
      )
    ) {
      return requestError(response, 405, 'Method not allowed.');
    }

    const token = bearerToken(request);
    let session;

    try {
      session = await findSession(token);
    } catch (error) {
      console.error('Database proxy session check failed.', error);

      return requestError(
        response,
        503,
        'Unable to validate your session.',
      );
    }

    if (!session) {
      return requestError(
        response,
        401,
        'Your session has expired. Please sign in.',
      );
    }

    try {
      const account = await loadAccount(session.userId);

      if (!account) {
        return requestError(
          response,
          401,
          'Your session has expired. Please sign in.',
        );
      }

      const upstreamUrl = new URL(
        request.originalUrl,
        `${config.supabaseUrl}/`,
      );

      const jwt = signDatabaseJwt({
        userId: session.userId,
        sessionId: session.id,
        email: account.email,
        secret: config.jwtSecret,
      });

      const headers = new Headers({
        apikey: config.supabaseAnonKey,
        authorization: `Bearer ${jwt}`,
        accept: request.get('accept') ?? 'application/json',
      });

      for (const name of [
        'content-type',
        'prefer',
        'range',
        'accept-profile',
        'content-profile',
        'x-client-info',
      ]) {
        const value = request.get(name);
        if (value) headers.set(name, value);
      }

      const upstream = await fetch(upstreamUrl, {
        method: request.method,
        headers,
        body: ['GET', 'HEAD'].includes(request.method)
          ? undefined
          : request.body,
        signal: AbortSignal.timeout(20000),
      });

      for (const name of [
        'content-type',
        'content-range',
        'range-unit',
        'preference-applied',
        'location',
        'content-location',
        'etag',
      ]) {
        const value = upstream.headers.get(name);
        if (value) response.setHeader(name, value);
      }

      response.status(upstream.status);

      if (request.method === 'HEAD') {
        return response.end();
      }

      return response.send(
        Buffer.from(await upstream.arrayBuffer()),
      );
    } catch (error) {
      console.error('Database proxy request failed.', error);

      return requestError(
        response,
        502,
        'The database request could not be completed.',
      );
    }
  },
);

// JSON body parser for API endpoints
app.use(express.json({ limit: '32kb' }));

function validRequestFields(request, response, fields) {
  const body = request.body;

  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    requestError(response, 400, 'Invalid request.');
    return false;
  }

  for (const field of fields) {
    if (typeof body[field] !== 'string') {
      requestError(
        response,
        400,
        'Please check all required fields.',
      );
      return false;
    }
  }

  return true;
}

// -----------------------------------------------------------------------------
// 1. REGISTRATION
// -----------------------------------------------------------------------------

app.post('/register', async (request, response) => {
  const required = [
    'username',
    'email',
    'dateOfBirth',
    'password',
    'confirmPassword',
  ];

  if (!validRequestFields(request, response, required)) return;

  const username = request.body.username.trim();
  const email = normalizeEmail(request.body.email);
  const dateOfBirth = request.body.dateOfBirth.trim();
  const password = request.body.password;
  const confirmPassword = request.body.confirmPassword;

  if (!validUsername(username)) {
    return requestError(
      response,
      400,
      'Username must be 3–30 letters, numbers, or underscores.',
    );
  }

  if (!validEmail(email)) {
    return requestError(response, 400, 'Enter a valid email address.');
  }

  if (!validDateOfBirth(dateOfBirth)) {
    return requestError(
      response,
      400,
      'Enter a valid date of birth (YYYY-MM-DD) not in the future.',
    );
  }

  if (!passwordsMatch(password, confirmPassword)) {
    return requestError(response, 400, 'Passwords do not match.');
  }

  const passwordError = validatePassword(password);

  if (passwordError) {
    return requestError(response, 400, passwordError);
  }

  const normalizedUser = normalizeUsername(username);

  const allowed = await rateLimitPasses(
    request,
    'custom-register',
    `${normalizedUser}:${email}`,
    8,
    900,
  );

  if (!allowed) {
    return requestError(
      response,
      429,
      'Too many registration attempts. Please try again later.',
    );
  }

  try {
    const { data: existingUser } = await admin
      .from('user_accounts')
      .select('id, username, email')
      .or(`username.ilike.${normalizedUser},email.ilike.${email}`)
      .limit(1)
      .maybeSingle();

    if (existingUser) {
      if (existingUser.username?.toLowerCase() === normalizedUser) {
        return requestError(
          response,
          409,
          'This username is already taken.',
        );
      }

      if (existingUser.email?.toLowerCase() === email) {
        return requestError(
          response,
          409,
          'An account with this email already exists.',
        );
      }
    }

    const passwordHash = await hashPassword(password);

    const { data: accountId, error } = await admin.rpc(
      'custom_register_account',
      {
        p_username: normalizedUser,
        p_email: email,
        p_dob: dateOfBirth,
        p_password_hash: passwordHash,
      },
    );

    if (error) {
      const message = error.message || '';

      if (message.includes('username_ci_unique')) {
        return requestError(
          response,
          409,
          'This username is already taken.',
        );
      }

      if (message.includes('email_ci_unique')) {
        return requestError(
          response,
          409,
          'An account with this email already exists.',
        );
      }

      console.error('Registration failed:', error);

      return requestError(
        response,
        500,
        'Unable to create your account.',
      );
    }

    return response.status(201).json({
      success: true,
      id: accountId,
      message: 'Account created successfully. You can now log in.',
    });
  } catch (error) {
    console.error('Registration exception:', error);

    return requestError(
      response,
      503,
      'Unable to register. Please try again later.',
    );
  }
});

// -----------------------------------------------------------------------------
// 2. LOGIN
// -----------------------------------------------------------------------------

app.post('/login', async (request, response) => {
  if (!validRequestFields(request, response, ['identifier', 'password'])) {
    return;
  }

  const identifier = request.body.identifier.trim();
  const password = request.body.password;
  const isEmail = identifier.includes('@');

  const normalizedIdentity = isEmail
    ? normalizeEmail(identifier)
    : normalizeUsername(identifier);

  if (
    !password ||
    (isEmail
      ? !validEmail(normalizedIdentity)
      : !validUsername(identifier))
  ) {
    return requestError(
      response,
      401,
      'Invalid username/email or password.',
    );
  }

  const allowed = await rateLimitPasses(
    request,
    'custom-login',
    normalizedIdentity,
    6,
    900,
  );

  if (!allowed) {
    return requestError(
      response,
      429,
      'Too many login attempts. Please wait 15 minutes.',
    );
  }

  try {
    const { data: account, error } = await admin
      .from('user_accounts')
      .select('id, username, email, password_hash')
      .ilike(isEmail ? 'email' : 'username', normalizedIdentity)
      .maybeSingle();

    if (error || !account) {
      return requestError(
        response,
        401,
        'Invalid username/email or password.',
      );
    }

    if (!account.password_hash) {
      return requestError(
        response,
        401,
        'This account has not set a password yet. Please use Forgot Password to set your password.',
      );
    }

    const isMatch = await verifyPassword(
      password,
      account.password_hash,
    );

    if (!isMatch) {
      return requestError(
        response,
        401,
        'Invalid username/email or password.',
      );
    }

    if (account.password_hash.startsWith('$2')) {
      const upgraded = await hashPassword(password);

      await admin
        .from('user_accounts')
        .update({
          password_hash: upgraded,
          updated_at: new Date().toISOString(),
        })
        .eq('id', account.id);
    }

    const token = newOpaqueToken();
    const sessionId = randomUUID();
    const expiresAt = new Date(
      Date.now() + SESSION_LIFETIME_MS,
    ).toISOString();

    const { error: sessionError } = await admin
      .from('user_sessions')
      .insert({
        id: sessionId,
        account_id: account.id,
        token_hash: sha256Hex(token),
        expires_at: expiresAt,
        is_revoked: false,
      });

    if (sessionError) {
      console.error('Session insert error:', sessionError);

      return requestError(
        response,
        500,
        'Unable to create session.',
      );
    }

    const user = await loadAccount(account.id);

    return response.json({
      token,
      expiresAt,
      userId: account.id,
      user,
    });
  } catch (error) {
    console.error('Login exception:', error);

    return requestError(
      response,
      503,
      'Unable to sign in. Please try again.',
    );
  }
});

// -----------------------------------------------------------------------------
// 3. FORGOT PASSWORD - VERIFY ACCOUNT DETAILS
// -----------------------------------------------------------------------------

app.post('/forgot-password/verify', async (request, response) => {
  const required = ['username', 'email', 'dateOfBirth'];

  if (!validRequestFields(request, response, required)) return;

  const username = normalizeUsername(request.body.username);
  const email = normalizeEmail(request.body.email);
  const dob = request.body.dateOfBirth.trim();

  if (
    !validUsername(username) ||
    !validEmail(email) ||
    !validDateOfBirth(dob)
  ) {
    return requestError(
      response,
      400,
      'Please check your information and try again.',
    );
  }

  const allowed = await rateLimitPasses(
    request,
    'custom-forgot-verify',
    `${username}:${email}`,
    6,
    900,
  );

  if (!allowed) {
    return requestError(
      response,
      429,
      'Too many verification attempts. Please wait 15 minutes.',
    );
  }

  try {
    const { data: account, error } = await admin
      .from('user_accounts')
      .select('id')
      .ilike('username', username)
      .ilike('email', email)
      .eq('dob', dob)
      .maybeSingle();

    if (error || !account) {
      return requestError(
        response,
        400,
        'The provided details do not match any existing account. Please verify your details.',
      );
    }

    const rawResetToken = randomBytes(32).toString('hex');
    const tokenHash = sha256Hex(rawResetToken);

    const expiresAt = new Date(
      Date.now() + RESET_TOKEN_LIFETIME_MS,
    ).toISOString();

    await admin
      .from('password_reset_authorizations')
      .update({ is_used: true })
      .eq('account_id', account.id)
      .eq('is_used', false);

    const { error: tokenError } = await admin
      .from('password_reset_authorizations')
      .insert({
        account_id: account.id,
        reset_token_hash: tokenHash,
        expires_at: expiresAt,
        is_used: false,
      });

    if (tokenError) {
      console.error('Reset token creation error:', tokenError);

      return requestError(
        response,
        500,
        'Unable to initiate password reset.',
      );
    }

    return response.json({
      success: true,
      resetToken: rawResetToken,
      expiresInMinutes: 10,
    });
  } catch (error) {
    console.error('Forgot password verify exception:', error);

    return requestError(
      response,
      503,
      'Unable to complete verification.',
    );
  }
});

// -----------------------------------------------------------------------------
// 4. FORGOT PASSWORD - SET NEW PASSWORD
// -----------------------------------------------------------------------------

app.post('/forgot-password/reset', async (request, response) => {
  const required = [
    'resetToken',
    'password',
    'confirmPassword',
  ];

  if (!validRequestFields(request, response, required)) return;

  const resetToken = request.body.resetToken.trim();
  const password = request.body.password;
  const confirmPassword = request.body.confirmPassword;

  if (resetToken.length !== 64) {
    return requestError(
      response,
      400,
      'Invalid or expired reset session.',
    );
  }

  if (!passwordsMatch(password, confirmPassword)) {
    return requestError(response, 400, 'Passwords do not match.');
  }

  const passwordError = validatePassword(password);

  if (passwordError) {
    return requestError(response, 400, passwordError);
  }

  const tokenHash = sha256Hex(resetToken);

  const allowed = await rateLimitPasses(
    request,
    'custom-forgot-reset',
    tokenHash,
    4,
    900,
  );

  if (!allowed) {
    return requestError(
      response,
      429,
      'Too many reset attempts. Please start over.',
    );
  }

  try {
    if (pgPool) {
      const client = await pgPool.connect();

      try {
        await client.query('BEGIN');

        const tokenResult = await client.query(
          `SELECT id, account_id, expires_at, is_used
           FROM public.password_reset_authorizations
           WHERE reset_token_hash = $1
           FOR UPDATE`,
          [tokenHash],
        );

        const authRow = tokenResult.rows[0];

        if (
          !authRow ||
          authRow.is_used ||
          new Date(authRow.expires_at) <= new Date()
        ) {
          await client.query('ROLLBACK');

          return requestError(
            response,
            400,
            'Your password reset session has expired or has already been used. Please verify your details again.',
          );
        }

        await client.query(
          `UPDATE public.password_reset_authorizations
           SET is_used = true
           WHERE id = $1`,
          [authRow.id],
        );

        const newHash = await hashPassword(password);

        await client.query(
          `UPDATE public.user_accounts
           SET password_hash = $1, updated_at = now()
           WHERE id = $2`,
          [newHash, authRow.account_id],
        );

        await client.query(
          `UPDATE public.user_sessions
           SET is_revoked = true
           WHERE account_id = $1`,
          [authRow.account_id],
        );

        await client.query('COMMIT');

        return response.json({
          success: true,
          message: 'Password reset successfully. You can now log in with your new password.',
        });
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    }

    const newHash = await hashPassword(password);

    const { data: success, error: resetError } = await admin.rpc(
      'custom_reset_password_atomic',
      {
        p_reset_token_hash: tokenHash,
        p_new_password_hash: newHash,
      },
    );

    if (resetError || success !== true) {
      return requestError(
        response,
        400,
        'Your password reset session has expired or has already been used. Please verify your details again.',
      );
    }

    return response.json({
      success: true,
      message: 'Password reset successfully. You can now log in with your new password.',
    });
  } catch (error) {
    console.error('Reset password exception:', error);

    return requestError(
      response,
      503,
      'Unable to reset password.',
    );
  }
});

// -----------------------------------------------------------------------------
// 5. SESSION
// -----------------------------------------------------------------------------

app.get('/session', async (request, response) => {
  const session = await requireSession(request, response);
  if (!session) return;

  try {
    const user = await loadAccount(session.userId);

    if (!user) {
      return requestError(
        response,
        401,
        'Your session has expired.',
      );
    }

    return response.json({
      user,
      expiresAt: session.expiresAt,
    });
  } catch (error) {
    console.error('Session load error:', error);

    return requestError(
      response,
      503,
      'Unable to load session.',
    );
  }
});

// -----------------------------------------------------------------------------
// GOOGLE CALENDAR CONFIGURATION CHECK
// -----------------------------------------------------------------------------

function requireGoogleCalendarConfig(response) {
  if (!pgPool) {
    response.status(503).json({
      error: 'Google Calendar requires DATABASE_URL to be configured.',
    });
    return false;
  }

  if (
    !config.encryptionKey ||
    !config.googleClientId ||
    !config.googleClientSecret ||
    !config.googleRedirectUri
  ) {
    response.status(503).json({
      error: 'Google Calendar is not fully configured on the server.',
    });
    return false;
  }

  return true;
}

// -----------------------------------------------------------------------------
// CALENDAR AUTHENTICATION BRIDGE
// -----------------------------------------------------------------------------

export const requireCalendarAuth = createRequireCalendarAuth({
  admin,
  findSession,
  pgPool,
  requestError,
});

// -----------------------------------------------------------------------------
// GOOGLE CALENDAR ROUTES
// -----------------------------------------------------------------------------

// 1. GET /api/calendar/auth-url
app.get('/api/calendar/auth-url', async (req, res) => {
  const session = await requireCalendarAuth(req, res);
  if (!session) return;

  if (!requireGoogleCalendarConfig(res)) return;

  try {
    const result = await getAuthUrl(
      pgPool,
      session.userId,
      config,
    );

    return res.json(result);
  } catch (error) {
    console.error('Error generating Google Calendar auth URL:', error);

    return res.status(500).json({
      error: 'Unable to start Google Calendar authorization.',
    });
  }
});

// 2. GET /api/calendar/callback
// Google redirects here. This route is intentionally public;
// the OAuth state must be validated by handleOAuthCallback().
app.get('/api/calendar/callback', async (req, res) => {
  if (!requireGoogleCalendarConfig(res)) return;

  const { code, state, error: googleError } = req.query;

  if (googleError) {
    return res.status(400).send(
      'Google Calendar authorization was cancelled or denied. You can return to Eleven11 and try again.',
    );
  }

  if (
    typeof code !== 'string' ||
    typeof state !== 'string' ||
    !code ||
    !state
  ) {
    return res.status(400).send(
      'Google Calendar authorization failed. Please return to Eleven11 and try again.',
    );
  }

  try {
    const result = await handleOAuthCallback(
      pgPool,
      code,
      state,
      config,
    );

    const email = encodeURIComponent(result.googleEmail || '');

    return res.redirect(
      `com.eleven11.eleven11://google-calendar-callback?status=success&email=${email}`,
    );
  } catch (error) {
    console.error('Error handling Google Calendar callback:', error);

    return res.status(400).send(
      'Google Calendar authorization failed. Please return to Eleven11 and try again.',
    );
  }
});

// 3. GET /api/calendar/status
app.get('/api/calendar/status', async (req, res) => {
  const session = await requireCalendarAuth(req, res);
  if (!session) return;

  // ADDED: Check Google Calendar configuration before querying.
  if (!requireGoogleCalendarConfig(res)) return;

  try {
    const status = await getCalendarStatus(
      pgPool,
      session.userId,
    );

    return res.json(status);
  } catch (error) {
    console.error('Error fetching calendar status:', error);

    return res.status(500).json({
      error: 'Unable to fetch Google Calendar status.',
    });
  }
});

// 4. POST /api/calendar/disconnect
app.post('/api/calendar/disconnect', async (req, res) => {
  const session = await requireCalendarAuth(req, res);
  if (!session) return;

  if (!requireGoogleCalendarConfig(res)) return;

  try {
    const result = await disconnectCalendar(
      pgPool,
      session.userId,
      config,
    );

    return res.json(result);
  } catch (error) {
    console.error('Error disconnecting calendar:', error);

    return res.status(500).json({
      error: 'Unable to disconnect Google Calendar.',
    });
  }
});

// 5. POST /api/calendar/sync-event
app.post('/api/calendar/sync-event', async (req, res) => {
  const session = await requireCalendarAuth(req, res);
  if (!session) return;

  if (!requireGoogleCalendarConfig(res)) return;

  try {
    const event = await pushEventToGoogle(
      pgPool,
      session.userId,
      req.body,
      config,
    );

    return res.json(event);
  } catch (error) {
    console.error('Error syncing event to Google:', error);

    return res.status(500).json({
      error: 'Unable to sync event to Google Calendar.',
    });
  }
});

// 6. POST /api/calendar/delete-event
app.post('/api/calendar/delete-event', async (req, res) => {
  const session = await requireCalendarAuth(req, res);
  if (!session) return;

  if (!requireGoogleCalendarConfig(res)) return;

  const { eventId } = req.body || {};

  if (!eventId) {
    return res.status(400).json({
      error: 'Missing required eventId.',
    });
  }

  try {
    const result = await deleteEventFromGoogle(
      pgPool,
      session.userId,
      eventId,
      config,
    );

    return res.json(result);
  } catch (error) {
    console.error('Error deleting event from Google:', error);

    return res.status(500).json({
      error: 'Unable to delete event from Google Calendar.',
    });
  }
});

// 7. POST /api/calendar/pull-sync
app.post('/api/calendar/pull-sync', async (req, res) => {
  const session = await requireCalendarAuth(req, res);
  if (!session) return;

  if (!requireGoogleCalendarConfig(res)) return;

  try {
    const result = await pullSyncGoogleCalendar(
      pgPool,
      session.userId,
      config,
    );

    return res.json(result);
  } catch (error) {
    console.error('Error during Google Calendar pull sync:', error);

    return res.status(500).json({
      error: 'Unable to sync events from Google Calendar.',
    });
  }
});

// -----------------------------------------------------------------------------
// ADMIN AUTHORIZATION MIDDLEWARE & ENDPOINTS
// -----------------------------------------------------------------------------

const DESIGNATED_ADMIN_UUID = '74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a';

const adminHandlers = createAdminHandlers({
  requireAuth: requireCalendarAuth,
  admin,
  pgPool,
  requestError,
  designatedAdminUuid: DESIGNATED_ADMIN_UUID,
});

// User activity tracking endpoints (authenticated end-users)
app.post('/api/activity/auth-event', adminHandlers.recordAuthEvent);
app.post('/api/activity/heartbeat', adminHandlers.recordHeartbeat);

// Direct password recovery endpoints (verify identity -> reset password)
app.post('/api/auth/verify-recovery', async (request, response) => {
  const { username, email, dateOfBirth } = request.body || {};
  if (
    typeof username !== 'string' ||
    typeof email !== 'string' ||
    typeof dateOfBirth !== 'string' ||
    !validUsername(username.trim()) ||
    !validEmail(normalizeEmail(email)) ||
    !/^\d{4}-\d{2}-\d{2}$/.test(dateOfBirth.trim())
  ) {
    return requestError(response, 400, 'Enter a valid username, email, and date of birth.');
  }

  try {
    const { data, error } = await admin.rpc('auth_recovery_identity', {
      p_username: username.trim(),
      p_email: normalizeEmail(email),
      p_date_of_birth: dateOfBirth.trim(),
    });
    if (error) {
      console.error('Recovery identity lookup failed:', error);
      return requestError(response, 503, 'Unable to verify account details. Please try again.');
    }

    const account = Array.isArray(data) ? data[0] : null;
    if (!account || typeof account.user_id !== 'string') {
      return requestError(response, 404, 'Account details do not match our records.');
    }

    return response.json({ verified: true });
  } catch (err) {
    console.error('Error in /api/auth/verify-recovery:', err);
    return requestError(response, 500, 'Unable to verify account details.');
  }
});

app.post('/api/auth/reset-password', async (request, response) => {
  const { username, email, dateOfBirth, password } = request.body || {};
  if (
    typeof username !== 'string' ||
    typeof email !== 'string' ||
    typeof dateOfBirth !== 'string' ||
    typeof password !== 'string' ||
    !validUsername(username.trim()) ||
    !validEmail(normalizeEmail(email)) ||
    !/^\d{4}-\d{2}-\d{2}$/.test(dateOfBirth.trim())
  ) {
    return requestError(response, 400, 'Invalid recovery details.');
  }

  const passwordError = validatePassword(password);
  if (passwordError) {
    return requestError(response, 400, passwordError);
  }

  try {
    const { data, error } = await admin.rpc('auth_recovery_identity', {
      p_username: username.trim(),
      p_email: normalizeEmail(email),
      p_date_of_birth: dateOfBirth.trim(),
    });
    if (error) {
      console.error('Recovery identity lookup failed:', error);
      return requestError(response, 503, 'Unable to reset password. Please try again.');
    }

    const account = Array.isArray(data) ? data[0] : null;
    if (!account || typeof account.user_id !== 'string') {
      return requestError(response, 404, 'Account details do not match our records.');
    }

    const { error: updateError } = await admin.auth.admin.updateUserById(
      account.user_id,
      { password },
    );
    if (updateError) {
      console.error('Password update failed:', updateError);
      return requestError(response, 500, 'Unable to update password. Please try again.');
    }

    return response.json({ reset: true });
  } catch (err) {
    console.error('Error in /api/auth/reset-password:', err);
    return requestError(response, 500, 'Unable to reset password.');
  }
});

// Admin panel endpoints (designated admin UUID or admin_roles)
app.get('/api/admin/metrics', adminHandlers.getMetrics);
app.get('/api/admin/users', adminHandlers.getUsers);
app.get('/api/admin/users/:userId/activity', adminHandlers.getUserActivity);
app.get('/api/admin/feedback', adminHandlers.getFeedback);
app.patch('/api/admin/feedback/:id', adminHandlers.patchFeedback);

// -----------------------------------------------------------------------------
// LOGOUT
// -----------------------------------------------------------------------------

app.post('/logout', async (request, response) => {
  const session = await requireSession(request, response);
  if (!session) return;

  try {
    await admin
      .from('user_sessions')
      .update({ is_revoked: true })
      .eq('id', session.id);

    return response.status(204).end();
  } catch (error) {
    console.error('Logout error:', error);

    return requestError(
      response,
      503,
      'Unable to end session.',
    );
  }
});

// -----------------------------------------------------------------------------
// GLOBAL ERROR HANDLER
// -----------------------------------------------------------------------------

app.use((error, _request, response, _next) => {
  if (error?.type === 'entity.too.large') {
    return requestError(
      response,
      413,
      'Request payload too large.',
    );
  }

  console.error('Unhandled server error:', error);

  return requestError(
    response,
    500,
    'The request could not be completed.',
  );
});

// -----------------------------------------------------------------------------
// START SERVER
// -----------------------------------------------------------------------------

export const server = app.listen(
  config.port,
  '0.0.0.0',
  () => {
    console.log(
      `Eleven11 Custom Auth API running on port ${config.port}`,
    );
  },
);
