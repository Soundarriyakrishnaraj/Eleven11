
import {
  createHash,
  randomBytes,
  randomUUID,
} from 'node:crypto';

import { google } from 'googleapis';
import {
  decryptAes256Gcm,
  encryptAes256Gcm,
} from './security.js';

const GOOGLE_CALENDAR_SCOPE = [
  'https://www.googleapis.com/auth/calendar.events',
  'https://www.googleapis.com/auth/calendar.app.created',
  'https://www.googleapis.com/auth/calendar.calendarlist.readonly',
].join(' ');

const GOOGLE_EMAIL_SCOPE =
  'https://www.googleapis.com/auth/userinfo.email';

const LEASE_SECONDS = 120;
const OAUTH_STATE_MINUTES = 10;

function httpError(message, status = 500) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function requireDatabase(db) {
  if (
    !db ||
    typeof db.query !== 'function' ||
    typeof db.connect !== 'function'
  ) {
    throw httpError('Google Calendar requires a PostgreSQL pool.', 503);
  }
}

function requireConfig(config) {
  if (
    !config?.googleClientId ||
    !config?.googleClientSecret ||
    !config?.googleRedirectUri ||
    !config?.encryptionKey
  ) {
    throw httpError('Google Calendar is not configured on the server.', 503);
  }

  if (
    !Buffer.isBuffer(config.encryptionKey) ||
    config.encryptionKey.length !== 32
  ) {
    throw httpError('Google Calendar encryption key is invalid.', 503);
  }
}

function isUuid(value) {
  return typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function base64UrlEncode(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function makeOAuthClient(config) {
  if (config.oauth2ClientFactory) {
    return config.oauth2ClientFactory(config);
  }

  return new google.auth.OAuth2(
    config.googleClientId,
    config.googleClientSecret,
    config.googleRedirectUri,
  );
}

function makeCalendarClient(oauth, config) {
  if (config.calendarClientFactory) {
    return config.calendarClientFactory(oauth);
  }

  return google.calendar({ version: 'v3', auth: oauth });
}

function makeUserInfoClient(oauth, config) {
  if (config.userInfoClientFactory) {
    return config.userInfoClientFactory(oauth);
  }

  return google.oauth2({ version: 'v2', auth: oauth }).userinfo;
}

export function createOAuth2Client(config) {
  requireConfig(config);
  return makeOAuthClient(config);
}

export function uuidToGoogleEventId(uuid) {
  if (!isUuid(uuid)) {
    throw httpError('Invalid Eleven11 event ID.', 400);
  }

  return `el${uuid.replace(/-/g, '').toLowerCase()}`;
}

function parseDateOnly(value) {
  if (
    typeof value !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  ) {
    throw httpError('All-day events require dates in YYYY-MM-DD format.', 400);
  }

  const parsed = new Date(`${value}T00:00:00.000Z`);

  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== value
  ) {
    throw httpError('Invalid all-day event date.', 400);
  }

  return value;
}

function allDayDateToStorage(value) {
  return `${parseDateOnly(value)}T12:00:00.000Z`;
}

function storageToAllDayDate(value) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw httpError('Invalid stored all-day event date.', 500);
  }

  return date.toISOString().slice(0, 10);
}

function getEventDate(value, fieldName) {
  if (typeof value !== 'string' || !value.trim()) {
    throw httpError(`${fieldName} is required.`, 400);
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw httpError(`${fieldName} is invalid.`, 400);
  }

  return date;
}

function validateEventInput(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw httpError('Invalid event request.', 400);
  }

  if (!isUuid(input.id)) {
    throw httpError('A valid Eleven11 event ID is required.', 400);
  }

  if (
    typeof input.idempotencyKey !== 'string' ||
    input.idempotencyKey.length < 8 ||
    input.idempotencyKey.length > 200
  ) {
    throw httpError('A valid idempotency key is required.', 400);
  }

  if (typeof input.title !== 'string' || input.title.length > 1024) {
    throw httpError('Event title is invalid.', 400);
  }

  const isAllDay = input.isAllDay === true;
  let startTime;
  let endTime;

  if (isAllDay) {
    startTime = allDayDateToStorage(input.startTime);
    endTime = allDayDateToStorage(input.endTime);

    if (new Date(endTime) <= new Date(startTime)) {
      throw httpError('All-day event end date must be after its start date.', 400);
    }
  } else {
    startTime = getEventDate(input.startTime, 'Start time').toISOString();
    endTime = getEventDate(input.endTime, 'End time').toISOString();

    if (new Date(endTime) <= new Date(startTime)) {
      throw httpError('Event end time must be after its start time.', 400);
    }
  }

  const timezone = input.timezone || 'UTC';

  try {
    new Intl.DateTimeFormat('en-US', { timeZone: timezone });
  } catch {
    throw httpError('Invalid event timezone.', 400);
  }

  const attendees = input.attendees ?? [];

  if (!Array.isArray(attendees) || attendees.length > 200) {
    throw httpError('Invalid event attendees.', 400);
  }

  const normalizedAttendees = attendees.map((attendee) => {
    const email = typeof attendee === 'string'
      ? attendee.trim()
      : attendee?.email?.trim();

    if (
      typeof email !== 'string' ||
      email.length > 320 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
    ) {
      throw httpError('An event attendee has an invalid email address.', 400);
    }

    return {
      email,
      ...(typeof attendee === 'object' && attendee?.displayName
        ? { displayName: String(attendee.displayName).slice(0, 256) }
        : {}),
    };
  });

  const reminderMinutes = Number(input.reminderMinutes ?? 15);

  if (
    !Number.isInteger(reminderMinutes) ||
    reminderMinutes < 0 ||
    reminderMinutes > 40320
  ) {
    throw httpError('Reminder must be between 0 and 40320 minutes.', 400);
  }

  const recurrenceRules = input.recurrenceRules ?? null;

  if (
    recurrenceRules !== null &&
    (
      !Array.isArray(recurrenceRules) ||
      recurrenceRules.length > 20 ||
      recurrenceRules.some((rule) =>
        typeof rule !== 'string' ||
        !rule.startsWith('RRULE:') ||
        rule.length > 2048
      )
    )
  ) {
    throw httpError('Invalid recurrence rules.', 400);
  }

  return {
    id: input.id,
    idempotencyKey: input.idempotencyKey,
    title: input.title,
    description: typeof input.description === 'string'
      ? input.description.slice(0, 20000)
      : null,
    location: typeof input.location === 'string'
      ? input.location.slice(0, 2000)
      : null,
    startTime,
    endTime,
    timezone,
    isAllDay,
    attendees: normalizedAttendees,
    reminderMinutes,
    recurrenceRules,
  };
}

// -----------------------------------------------------------------------------
// OAuth authorization
// -----------------------------------------------------------------------------

export async function getAuthUrl(db, userId, config) {
  requireDatabase(db);
  requireConfig(config);

  if (!isUuid(userId)) {
    throw httpError('Invalid authenticated user.', 401);
  }

  const verifier = base64UrlEncode(randomBytes(32));
  const challenge = base64UrlEncode(
    createHash('sha256').update(verifier).digest(),
  );
  const state = randomBytes(32).toString('hex');

  const encryptedVerifier = encryptAes256Gcm(
    verifier,
    config.encryptionKey,
  );

  await db.query(
    `INSERT INTO public.google_oauth_states
      (user_id, state_token, encrypted_code_verifier, expires_at, is_used)
     VALUES ($1, $2, $3, now() + interval '${OAUTH_STATE_MINUTES} minutes', false)`,
    [userId, state, encryptedVerifier],
  );

  const oauth = makeOAuthClient(config);

  return {
    authUrl: oauth.generateAuthUrl({
      access_type: 'offline',
      prompt: 'consent',
      scope: [GOOGLE_CALENDAR_SCOPE, GOOGLE_EMAIL_SCOPE],
      state,
      code_challenge: challenge,
      code_challenge_method: 'S256',
    }),
  };
}

// -----------------------------------------------------------------------------
// OAuth callback
// -----------------------------------------------------------------------------

export async function handleOAuthCallback(db, code, stateToken, config) {
  requireDatabase(db);
  requireConfig(config);

  if (
    typeof code !== 'string' ||
    !code ||
    typeof stateToken !== 'string' ||
    !/^[0-9a-f]{64}$/i.test(stateToken)
  ) {
    throw httpError('Invalid Google authorization callback.', 400);
  }

  const consumed = await db.query(
    `UPDATE public.google_oauth_states
     SET is_used = true
     WHERE state_token = $1
       AND is_used = false
       AND expires_at > now()
     RETURNING user_id, encrypted_code_verifier`,
    [stateToken],
  );

  if (!consumed.rows.length) {
    throw httpError(
      'OAuth state is invalid, expired, or has already been used.',
      400,
    );
  }

  const { user_id: userId, encrypted_code_verifier: encryptedVerifier } =
    consumed.rows[0];

  let verifier;

  try {
    verifier = decryptAes256Gcm(encryptedVerifier, config.encryptionKey);
  } catch {
    throw httpError('Unable to validate Google authorization. Please reconnect.', 400);
  }

  const oauth = makeOAuthClient(config);
  let tokens;

  try {
    const response = await oauth.getToken({
      code,
      codeVerifier: verifier,
    });

    tokens = response.tokens;
  } catch {
    throw httpError('Failed to exchange code with Google. Please try again.', 400);
  }

  if (!tokens?.access_token) {
    throw httpError('Google did not return an access token.', 400);
  }

  oauth.setCredentials(tokens);

  let googleEmail = null;

  try {
    const userInfo = makeUserInfoClient(oauth, config);
    const response = await userInfo.get();
    googleEmail = response.data?.email || null;
  } catch {
    // Google email is optional; calendar authorization can still succeed.
  }

  const existing = await db.query(
    `SELECT encrypted_refresh_token
     FROM public.user_google_calendar_tokens
     WHERE user_id = $1`,
    [userId],
  );

  let encryptedRefreshToken;

  if (tokens.refresh_token) {
    encryptedRefreshToken = encryptAes256Gcm(
      tokens.refresh_token,
      config.encryptionKey,
    );
  } else if (existing.rows[0]?.encrypted_refresh_token) {
    encryptedRefreshToken = existing.rows[0].encrypted_refresh_token;
  } else {
    throw httpError(
      'Google did not provide offline access. Please disconnect and authorize again.',
      400,
    );
  }

  const encryptedAccessToken = encryptAes256Gcm(
    tokens.access_token,
    config.encryptionKey,
  );

  await db.query(
    `INSERT INTO public.user_google_calendar_tokens (
       user_id, google_email, encrypted_access_token,
       encrypted_refresh_token, token_expires_at, scope, updated_at
     )
     VALUES ($1, $2, $3, $4, $5, $6, now())
     ON CONFLICT (user_id)
     DO UPDATE SET
       google_email = COALESCE(
         EXCLUDED.google_email,
         user_google_calendar_tokens.google_email
       ),
       encrypted_access_token = EXCLUDED.encrypted_access_token,
       encrypted_refresh_token = EXCLUDED.encrypted_refresh_token,
       token_expires_at = EXCLUDED.token_expires_at,
       scope = EXCLUDED.scope,
       updated_at = now()`,
    [
      userId,
      googleEmail,
      encryptedAccessToken,
      encryptedRefreshToken,
      new Date(tokens.expiry_date || Date.now() + 3600000),
      tokens.scope || GOOGLE_CALENDAR_SCOPE,
    ],
  );

  return { userId, googleEmail };
}

// -----------------------------------------------------------------------------
// Google token persistence
// -----------------------------------------------------------------------------

const refreshWriteQueues = new WeakMap();

function queueTokenPersistence(oauth, db, userId, config) {
  let pending = Promise.resolve();

  oauth.on('tokens', (tokens) => {
    pending = pending.then(async () => {
      if (!tokens.access_token && !tokens.refresh_token) return;

      const assignments = [];
      const values = [];
      let index = 1;

      if (tokens.access_token) {
        assignments.push(`encrypted_access_token = $${index++}`);
        values.push(encryptAes256Gcm(tokens.access_token, config.encryptionKey));
      }

      if (tokens.refresh_token) {
        assignments.push(`encrypted_refresh_token = $${index++}`);
        values.push(encryptAes256Gcm(tokens.refresh_token, config.encryptionKey));
      }

      if (tokens.expiry_date) {
        assignments.push(`token_expires_at = $${index++}`);
        values.push(new Date(tokens.expiry_date));
      }

      assignments.push('updated_at = now()');
      values.push(userId);

      await db.query(
        `UPDATE public.user_google_calendar_tokens
         SET ${assignments.join(', ')}
         WHERE user_id = $${index}`,
        values,
      );
    }).catch((error) => {
      console.error('Google token persistence failed:', error.message);
    });
  });

  refreshWriteQueues.set(oauth, () => pending);
}

export async function flushGoogleTokenWrites(oauth) {
  const flush = refreshWriteQueues.get(oauth);
  if (flush) await flush();
}

export async function getAuthenticatedGoogleClient(db, userId, config) {
  if (!db || typeof db.query !== 'function') {
    throw httpError('Google Calendar requires a PostgreSQL connection.', 503);
  }

  requireConfig(config);

  if (!isUuid(userId)) {
    throw httpError('Invalid authenticated user.', 401);
  }

  const result = await db.query(
    `SELECT encrypted_access_token,
            encrypted_refresh_token,
            token_expires_at
     FROM public.user_google_calendar_tokens
     WHERE user_id = $1`,
    [userId],
  );

  if (!result.rows.length) {
    throw httpError('No Google Calendar account is connected.', 404);
  }

  const row = result.rows[0];

  const oauth = makeOAuthClient(config);

  oauth.setCredentials({
    access_token: decryptAes256Gcm(
      row.encrypted_access_token,
      config.encryptionKey,
    ),
    refresh_token: decryptAes256Gcm(
      row.encrypted_refresh_token,
      config.encryptionKey,
    ),
    expiry_date: new Date(row.token_expires_at).getTime(),
  });

  queueTokenPersistence(oauth, db, userId, config);

  return oauth;
}

// -----------------------------------------------------------------------------
// Connection status
// -----------------------------------------------------------------------------

export async function getCalendarStatus(db, userId) {
  requireDatabase(db);

  if (!isUuid(userId)) {
    throw httpError('Invalid authenticated user.', 401);
  }

  const result = await db.query(
    `SELECT google_email, last_synced_at
     FROM public.user_google_calendar_tokens
     WHERE user_id = $1`,
    [userId],
  );

  if (!result.rows.length) {
    return { connected: false, email: null, lastSyncedAt: null };
  }

  return {
    connected: true,
    email: result.rows[0].google_email,
    lastSyncedAt: result.rows[0].last_synced_at,
  };
}

// -----------------------------------------------------------------------------
// Disconnect
// -----------------------------------------------------------------------------

export async function disconnectCalendar(db, userId, config) {
  requireDatabase(db);
  requireConfig(config);

  if (!isUuid(userId)) {
    throw httpError('Invalid authenticated user.', 401);
  }

  try {
    const oauth = await getAuthenticatedGoogleClient(db, userId, config);
    await oauth.revokeCredentials();
    await flushGoogleTokenWrites(oauth);
  } catch (error) {
    console.warn('Google token revocation was not completed:', error.message);
  }

  const client = await db.connect();

  try {
    await client.query('BEGIN');

    await client.query(
      `UPDATE public.events
       SET sync_with_google = false,
           sync_status = 'failed',
           sync_lease_until = NULL,
           sync_lease_owner = NULL,
           updated_at = now()
       WHERE user_id = $1`,
      [userId],
    );

    await client.query(
      `DELETE FROM public.user_google_calendar_tokens
       WHERE user_id = $1`,
      [userId],
    );

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }

  return { success: true };
}

// -----------------------------------------------------------------------------
// Reserve event and acquire a lease
// -----------------------------------------------------------------------------

async function reserveEvent(db, userId, event, workerToken) {
  const client = await db.connect();

  try {
    await client.query('BEGIN');

    let result = await client.query(
      `SELECT *
       FROM public.events
       WHERE user_id = $1 AND idempotency_key = $2
       FOR UPDATE`,
      [userId, event.idempotencyKey],
    );

    let record = result.rows[0];

    if (record && record.id !== event.id) {
      throw httpError(
        'This idempotency key is already assigned to a different event.',
        409,
      );
    }

    if (!record) {
      result = await client.query(
        `SELECT *
         FROM public.events
         WHERE id = $1 AND user_id = $2
         FOR UPDATE`,
        [event.id, userId],
      );

      record = result.rows[0];

      if (record?.idempotency_key &&
        record.idempotency_key !== event.idempotencyKey) {
        throw httpError(
          'This event ID is already associated with a different operation key.',
          409,
        );
      }

      if (!record) {
        try {
          const inserted = await client.query(
            `INSERT INTO public.events (
               id, user_id, idempotency_key, title, description, location,
               start_time, end_time, timezone, is_all_day, sync_with_google,
               reminder_minutes, attendees, recurrence_rules,
               status, sync_status
             )
             VALUES (
               $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, true,
               $11, $12::jsonb, $13, 'confirmed', 'pending'
             )
             RETURNING *`,
            [
              event.id,
              userId,
              event.idempotencyKey,
              event.title,
              event.description,
              event.location,
              event.startTime,
              event.endTime,
              event.timezone,
              event.isAllDay,
              event.reminderMinutes,
              JSON.stringify(event.attendees),
              event.recurrenceRules,
            ],
          );

          record = inserted.rows[0];
        } catch (error) {
          // A concurrent request may have inserted the same event/key.
          if (error.code !== '23505') throw error;

          const retry = await client.query(
            `SELECT *
             FROM public.events
             WHERE user_id = $1
               AND (id = $2 OR idempotency_key = $3)
             FOR UPDATE`,
            [userId, event.id, event.idempotencyKey],
          );

          record = retry.rows[0];

          if (!record || record.id !== event.id) {
            throw httpError('Event idempotency conflict.', 409);
          }
        }
      }
    }

    if (
      record.sync_status === 'syncing' &&
      record.sync_lease_until &&
      new Date(record.sync_lease_until) > new Date()
    ) {
      throw httpError('Operation in progress. Try again shortly.', 409);
    }

    const leased = await client.query(
      `UPDATE public.events
       SET title = $1,
           description = $2,
           location = $3,
           start_time = $4,
           end_time = $5,
           timezone = $6,
           is_all_day = $7,
           reminder_minutes = $8,
           attendees = $9::jsonb,
           recurrence_rules = $10,
           sync_with_google = true,
           sync_status = 'syncing',
           sync_lease_owner = $11,
           sync_lease_until = now() + interval '${LEASE_SECONDS} seconds',
           updated_at = now()
       WHERE id = $12 AND user_id = $13
       RETURNING *`,
      [
        event.title,
        event.description,
        event.location,
        event.startTime,
        event.endTime,
        event.timezone,
        event.isAllDay,
        event.reminderMinutes,
        JSON.stringify(event.attendees),
        event.recurrenceRules,
        workerToken,
        record.id,
        userId,
      ],
    );

    if (!leased.rows.length) {
      throw httpError('Could not acquire event synchronization lease.', 409);
    }

    await client.query('COMMIT');
    return leased.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function releaseFailedLease(db, userId, eventId, workerToken) {
  await db.query(
    `UPDATE public.events
     SET sync_status = 'failed',
         sync_lease_until = NULL,
         sync_lease_owner = NULL,
         updated_at = now()
     WHERE id = $1
       AND user_id = $2
       AND sync_lease_owner = $3`,
    [eventId, userId, workerToken],
  );
}

// -----------------------------------------------------------------------------
// Push event to Google
// -----------------------------------------------------------------------------

export async function pushEventToGoogle(db, userId, eventData, config) {
  requireDatabase(db);
  requireConfig(config);

  if (!isUuid(userId)) {
    throw httpError('Invalid authenticated user.', 401);
  }

  const event = validateEventInput(eventData);
  const workerToken = randomUUID();

  const record = await reserveEvent(db, userId, event, workerToken);

  try {
    const googleEventId = record.google_event_id ||
      uuidToGoogleEventId(record.id);

    const oauth = await getAuthenticatedGoogleClient(db, userId, config);
    const calendar = makeCalendarClient(oauth, config);

    const start = event.isAllDay
      ? { date: storageToAllDayDate(event.startTime) }
      : {
        dateTime: new Date(event.startTime).toISOString(),
        timeZone: event.timezone,
      };

    const end = event.isAllDay
      ? { date: storageToAllDayDate(event.endTime) }
      : {
        dateTime: new Date(event.endTime).toISOString(),
        timeZone: event.timezone,
      };

    const resource = {
      summary: event.title,
      start,
      end,
      attendees: event.attendees,
      reminders: {
        useDefault: false,
        overrides: event.reminderMinutes === 0
          ? []
          : [{ method: 'popup', minutes: event.reminderMinutes }],
      },
      extendedProperties: {
        private: {
          eleven11_event_id: record.id,
          eleven11_idempotency_key: event.idempotencyKey,
        },
      },
    };

    if (event.description !== null) resource.description = event.description;
    if (event.location !== null) resource.location = event.location;
    if (event.recurrenceRules?.length) {
      resource.recurrence = event.recurrenceRules;
    }

    let googleResult;

    if (record.google_event_id) {
      const patchParams = {
        calendarId: 'primary',
        eventId: record.google_event_id,
        sendUpdates: 'all',
        requestBody: resource,
      };

      if (record.google_etag) {
        patchParams.headers = { 'If-Match': record.google_etag };
      }

      try {
        googleResult = await calendar.events.patch(patchParams);
      } catch (error) {
        if (error.code === 412 || error.response?.status === 412) {
          throw httpError(
            'This event was changed in Google Calendar. Pull the latest calendar changes before editing it again.',
            409,
          );
        }
        throw error;
      }
    } else {
      resource.id = googleEventId;

      try {
        googleResult = await calendar.events.insert({
          calendarId: 'primary',
          sendUpdates: 'all',
          requestBody: resource,
        });
      } catch (error) {
        if (error.code !== 409 && error.response?.status !== 409) {
          throw error;
        }

        const existing = await calendar.events.get({
          calendarId: 'primary',
          eventId: googleEventId,
        });

        const privateProps = existing.data?.extendedProperties?.private || {};

        if (
          privateProps.eleven11_event_id !== record.id ||
          privateProps.eleven11_idempotency_key !== event.idempotencyKey
        ) {
          throw httpError(
            'The Google event ID already exists and does not belong to this Eleven11 event.',
            409,
          );
        }

        googleResult = existing;
      }
    }

    await flushGoogleTokenWrites(oauth);

    const finalized = await db.query(
      `UPDATE public.events
       SET google_event_id = $1,
           google_etag = $2,
           google_html_link = $3,
           sync_with_google = true,
           sync_status = 'synced',
           sync_lease_until = NULL,
           sync_lease_owner = NULL,
           updated_at = now()
       WHERE id = $4
         AND user_id = $5
         AND sync_lease_owner = $6
       RETURNING *`,
      [
        googleResult.data.id,
        googleResult.data.etag || null,
        googleResult.data.htmlLink || null,
        record.id,
        userId,
        workerToken,
      ],
    );

    if (!finalized.rows.length) {
      throw httpError(
        'The synchronization lease expired before the result could be saved. Please retry.',
        409,
      );
    }

    return finalized.rows[0];
  } catch (error) {
    try {
      await releaseFailedLease(db, userId, record.id, workerToken);
    } catch (releaseError) {
      console.error('Could not release failed event lease:', releaseError.message);
    }

    throw error;
  }
}

// -----------------------------------------------------------------------------
// Delete event
// -----------------------------------------------------------------------------

export async function deleteEventFromGoogle(db, userId, eventId, config) {
  requireDatabase(db);
  requireConfig(config);

  if (!isUuid(userId) || !isUuid(eventId)) {
    throw httpError('Invalid user or event ID.', 400);
  }

  const result = await db.query(
    `SELECT id, google_event_id
     FROM public.events
     WHERE id = $1 AND user_id = $2`,
    [eventId, userId],
  );

  if (!result.rows.length) {
    throw httpError('Event not found.', 404);
  }

  const googleEventId = result.rows[0].google_event_id;

  if (googleEventId) {
    const oauth = await getAuthenticatedGoogleClient(db, userId, config);
    const calendar = makeCalendarClient(oauth, config);

    try {
      await calendar.events.delete({
        calendarId: 'primary',
        eventId: googleEventId,
        sendUpdates: 'all',
      });
    } catch (error) {
      if (error.code !== 404 && error.response?.status !== 404) {
        await flushGoogleTokenWrites(oauth);
        throw error;
      }
    }

    await flushGoogleTokenWrites(oauth);
  }

  await db.query(
    `UPDATE public.events
     SET status = 'cancelled',
         sync_status = 'synced',
         sync_lease_until = NULL,
         sync_lease_owner = NULL,
         updated_at = now()
     WHERE id = $1 AND user_id = $2`,
    [eventId, userId],
  );

  return { success: true };
}

// -----------------------------------------------------------------------------
// Import Google events
// -----------------------------------------------------------------------------

async function processSingleGoogleEvent(client, userId, item) {
  if (!item?.id) return;

  if (item.status === 'cancelled') {
    if (item.recurringEventId && item.originalStartTime) {
      const original = item.originalStartTime;
      const originalValue = original.dateTime
        ? new Date(original.dateTime).toISOString()
        : allDayDateToStorage(original.date);

      await client.query(
        `INSERT INTO public.events (
           user_id, google_event_id, google_recurring_event_id,
           original_start_time, original_start_timezone,
           title, start_time, end_time, timezone, is_all_day,
           sync_with_google, status, sync_status
         )
         VALUES (
           $1, $2, $3, $4, $5, '(Cancelled occurrence)',
           $4, $4, $5, $6, true, 'cancelled', 'synced'
         )
         ON CONFLICT (user_id, google_event_id)
           WHERE google_event_id IS NOT NULL
         DO UPDATE SET
           status = 'cancelled',
           sync_status = 'synced',
           updated_at = now()`,
        [
          userId,
          item.id,
          item.recurringEventId,
          originalValue,
          original.timeZone || 'UTC',
          !original.dateTime,
        ],
      );

      return;
    }

    await client.query(
      `UPDATE public.events
       SET status = 'cancelled',
           sync_status = 'synced',
           updated_at = now()
       WHERE user_id = $1 AND google_event_id = $2`,
      [userId, item.id],
    );

    await client.query(
      `UPDATE public.events
       SET status = 'cancelled',
           sync_status = 'synced',
           updated_at = now()
       WHERE user_id = $1 AND google_recurring_event_id = $2`,
      [userId, item.id],
    );

    return;
  }

  const isAllDay = Boolean(item.start?.date);

  if (
    !item.start ||
    !item.end ||
    (isAllDay && (!item.start.date || !item.end.date)) ||
    (!isAllDay && (!item.start.dateTime || !item.end.dateTime))
  ) {
    throw httpError('Google returned an event with invalid start or end values.', 502);
  }

  const startValue = isAllDay
    ? allDayDateToStorage(item.start.date)
    : new Date(item.start.dateTime).toISOString();

  const endValue = isAllDay
    ? allDayDateToStorage(item.end.date)
    : new Date(item.end.dateTime).toISOString();

  if (new Date(endValue) < new Date(startValue)) {
    throw httpError('Google returned an event with an invalid time range.', 502);
  }

  const timezone = item.start.timeZone || 'UTC';

  const attendees = (item.attendees || []).map((attendee) => ({
    email: attendee.email,
    ...(attendee.displayName ? { displayName: attendee.displayName } : {}),
    ...(attendee.responseStatus
      ? { responseStatus: attendee.responseStatus }
      : {}),
  }));

  await client.query(
    `INSERT INTO public.events (
       user_id, google_event_id, google_etag, google_html_link,
       title, description, location, start_time, end_time, timezone,
       is_all_day, sync_with_google, recurrence_rules,
       google_recurring_event_id, original_start_time,
       original_start_timezone, attendees, status, sync_status
     )
     VALUES (
       $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
       $11, true, $12, $13, $14, $15, $16::jsonb, $17, 'synced'
     )
     ON CONFLICT (user_id, google_event_id)
       WHERE google_event_id IS NOT NULL
     DO UPDATE SET
       google_etag = EXCLUDED.google_etag,
       google_html_link = EXCLUDED.google_html_link,
       title = EXCLUDED.title,
       description = EXCLUDED.description,
       location = EXCLUDED.location,
       start_time = EXCLUDED.start_time,
       end_time = EXCLUDED.end_time,
       timezone = EXCLUDED.timezone,
       is_all_day = EXCLUDED.is_all_day,
       recurrence_rules = EXCLUDED.recurrence_rules,
       google_recurring_event_id = EXCLUDED.google_recurring_event_id,
       original_start_time = EXCLUDED.original_start_time,
       original_start_timezone = EXCLUDED.original_start_timezone,
       attendees = EXCLUDED.attendees,
       status = EXCLUDED.status,
       sync_status = 'synced',
       updated_at = now()
     WHERE events.user_id = $1`,
    [
      userId,
      item.id,
      item.etag || null,
      item.htmlLink || null,
      item.summary || '',
      item.description || null,
      item.location || null,
      startValue,
      endValue,
      timezone,
      isAllDay,
      item.recurrence || null,
      item.recurringEventId || null,
      item.originalStartTime?.dateTime
        ? new Date(item.originalStartTime.dateTime).toISOString()
        : item.originalStartTime?.date
          ? allDayDateToStorage(item.originalStartTime.date)
          : null,
      item.originalStartTime?.timeZone || null,
      JSON.stringify(attendees),
      ['confirmed', 'tentative'].includes(item.status)
        ? item.status
        : 'confirmed',
    ],
  );
}

// -----------------------------------------------------------------------------
// Incremental sync
// -----------------------------------------------------------------------------

export async function pullSyncGoogleCalendar(pool, userId, config) {
  requireDatabase(pool);
  requireConfig(config);

  if (!isUuid(userId)) {
    throw httpError('Invalid authenticated user.', 401);
  }

  const client = await pool.connect();
  const lockKey = `eleven11-google-calendar:${userId}`;
  let lockAcquired = false;
  let oauth;

  try {
    const lock = await client.query(
      'SELECT pg_try_advisory_lock(hashtextextended($1, 0)) AS locked',
      [lockKey],
    );

    lockAcquired = lock.rows[0]?.locked === true;

    if (!lockAcquired) {
      throw httpError(
        'Calendar synchronization is already running. Try again shortly.',
        409,
      );
    }

    // Use the same checked-out connection for token reads and token refresh
    // writes. This avoids deadlock when the pool has max=1.
    oauth = await getAuthenticatedGoogleClient(client, userId, config);
    const calendar = makeCalendarClient(oauth, config);

    for (let attempt = 0; attempt < 2; attempt++) {
      const tokenResult = await client.query(
        `SELECT next_sync_token
         FROM public.user_google_calendar_tokens
         WHERE user_id = $1`,
        [userId],
      );

      if (!tokenResult.rows.length) {
        throw httpError('No Google Calendar account is connected.', 404);
      }

      const syncToken = tokenResult.rows[0].next_sync_token;
      const isFullSync = !syncToken;

      let pageToken;
      let nextSyncToken = null;
      const importedItems = [];

      try {
        do {
          const response = await calendar.events.list({
            calendarId: 'primary',
            singleEvents: false,
            showDeleted: true,
            maxResults: 250,
            ...(syncToken ? { syncToken } : {}),
            ...(pageToken ? { pageToken } : {}),
          });

          for (const item of response.data.items || []) {
            importedItems.push(item);
          }

          pageToken = response.data.nextPageToken || undefined;

          if (response.data.nextSyncToken) {
            nextSyncToken = response.data.nextSyncToken;
          }
        } while (pageToken);

        if (!nextSyncToken) {
          throw httpError('Google did not return a completed sync token.', 502);
        }
      } catch (error) {
        if (
          attempt === 0 &&
          (error.code === 410 || error.response?.status === 410)
        ) {
          await client.query(
            `UPDATE public.user_google_calendar_tokens
             SET next_sync_token = NULL, updated_at = now()
             WHERE user_id = $1`,
            [userId],
          );

          continue;
        }

        throw error;
      }

      await client.query('BEGIN');

      try {
        for (const item of importedItems) {
          await processSingleGoogleEvent(client, userId, item);
        }

        // IMPORTANT:
        // Migration 015 has no source/origin column. We cannot safely tell
        // Eleven11-created events from Google-imported events. Therefore a
        // full sync must NOT prune rows missing from Google's response.

        await client.query(
          `UPDATE public.user_google_calendar_tokens
           SET next_sync_token = $1,
               last_synced_at = now(),
               updated_at = now()
           WHERE user_id = $2`,
          [nextSyncToken, userId],
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      }

      await flushGoogleTokenWrites(oauth);

      return {
        success: true,
        processedCount: importedItems.length,
        fullSync: isFullSync,
      };
    }

    throw httpError('Unable to complete Google Calendar synchronization.', 502);
  } finally {
    if (oauth) {
      await flushGoogleTokenWrites(oauth);
    }

    if (lockAcquired) {
      try {
        await client.query(
          'SELECT pg_advisory_unlock(hashtextextended($1, 0))',
          [lockKey],
        );
      } catch (error) {
        console.error('Could not release Google Calendar sync lock:', error.message);
      }
    }

    client.release();
  }
}


// ============================================================================
// Personal Google Calendar Task Sync
// ============================================================================

export async function listUserCalendars(db, userId, config) {
  requireDatabase(db);
  if (!isUuid(userId)) throw httpError('Invalid user ID.', 400);

  const oauth = await getAuthenticatedGoogleClient(db, userId, config);
  try {
    const calendar = makeCalendarClient(oauth, config);
    const res = await calendar.calendarList.list({ minAccessRole: 'writer' });
    const items = (res.data?.items || []).map((c) => ({
      id: c.id,
      summary: c.summary || c.id,
      primary: c.primary === true,
      timeZone: c.timeZone || 'Asia/Kolkata',
    }));
    return items;
  } finally {
    await flushGoogleTokenWrites(oauth);
  }
}

export async function createTasksCalendar(db, userId, config, timeZone = 'Asia/Kolkata') {
  requireDatabase(db);
  if (!isUuid(userId)) throw httpError('Invalid user ID.', 400);

  const oauth = await getAuthenticatedGoogleClient(db, userId, config);
  try {
    const calendar = makeCalendarClient(oauth, config);
    const created = await calendar.calendars.insert({
      requestBody: {
        summary: 'Eleven11 Tasks',
        description: 'Personal tasks synced from Eleven11.',
        timeZone: timeZone || 'Asia/Kolkata',
      },
    });
    const cal = created.data;
    await db.query(
      `UPDATE public.user_google_calendar_tokens
       SET selected_calendar_id = $2,
           selected_calendar_name = $3,
           updated_at = now()
       WHERE user_id = $1`,
      [userId, cal.id, cal.summary || 'Eleven11 Tasks'],
    );
    return {
      id: cal.id,
      summary: cal.summary || 'Eleven11 Tasks',
      timeZone: cal.timeZone || timeZone,
    };
  } finally {
    await flushGoogleTokenWrites(oauth);
  }
}

export async function getTaskSyncSettings(db, userId) {
  requireDatabase(db);
  if (!isUuid(userId)) throw httpError('Invalid user ID.', 400);

  const res = await db.query(
    `SELECT google_email, selected_calendar_id, selected_calendar_name,
            auto_task_sync, default_reminder_minutes
     FROM public.user_google_calendar_tokens
     WHERE user_id = $1`,
    [userId],
  );
  if (res.rows.length === 0) {
    return {
      connected: false,
      selectedCalendarId: 'primary',
      selectedCalendarName: null,
      autoTaskSync: false,
      defaultReminderMinutes: 15,
    };
  }
  const r = res.rows[0];
  return {
    connected: true,
    email: r.google_email,
    selectedCalendarId: r.selected_calendar_id || 'primary',
    selectedCalendarName: r.selected_calendar_name || null,
    autoTaskSync: r.auto_task_sync !== false,
    defaultReminderMinutes: Number.isInteger(r.default_reminder_minutes)
      ? r.default_reminder_minutes
      : 15,
  };
}

export async function updateTaskSyncSettings(db, userId, settings = {}) {
  requireDatabase(db);
  if (!isUuid(userId)) throw httpError('Invalid user ID.', 400);

  const fields = [];
  const values = [userId];
  let idx = 2;

  if (typeof settings.selectedCalendarId === 'string' && settings.selectedCalendarId.trim()) {
    fields.push(`selected_calendar_id = $${idx++}`);
    values.push(settings.selectedCalendarId.trim());
  }
  if (settings.selectedCalendarName !== undefined) {
    fields.push(`selected_calendar_name = $${idx++}`);
    values.push(settings.selectedCalendarName ? String(settings.selectedCalendarName).trim() : null);
  }
  if (typeof settings.autoTaskSync === 'boolean') {
    fields.push(`auto_task_sync = $${idx++}`);
    values.push(settings.autoTaskSync);
  }
  if (Number.isInteger(settings.defaultReminderMinutes) && settings.defaultReminderMinutes >= 0) {
    fields.push(`default_reminder_minutes = $${idx++}`);
    values.push(settings.defaultReminderMinutes);
  }

  if (fields.length > 0) {
    fields.push('updated_at = now()');
    await db.query(
      `UPDATE public.user_google_calendar_tokens SET ${fields.join(', ')} WHERE user_id = $1`,
      values,
    );
  }
  return getTaskSyncSettings(db, userId);
}

function buildTaskEventBody(task, defaultReminderMinutes) {
  const tz = (typeof task.timezone === 'string' && task.timezone.trim())
    ? task.timezone.trim()
    : 'Asia/Kolkata';
  const dateStr = String(task.due_date || '').split('T')[0];
  const timeStr = String(task.due_time || '09:00').slice(0, 5);
  const startLocal = `${dateStr}T${timeStr}:00`;

  let endLocal;
  if (task.end_time) {
    endLocal = `${dateStr}T${String(task.end_time).slice(0, 5)}:00`;
  } else {
    const [hh, mm] = timeStr.split(':').map((n) => parseInt(n, 10) || 0);
    const total = hh * 60 + mm + 30;
    const eh = String(Math.floor(total / 60) % 24).padStart(2, '0');
    const em = String(total % 60).padStart(2, '0');
    endLocal = `${dateStr}T${eh}:${em}:00`;
  }

  const isCompleted = task.is_completed === true;
  const rawTitle = String(task.title || 'Eleven11 Task').trim();
  const summary = isCompleted && !rawTitle.startsWith('✓ ')
    ? `✓ ${rawTitle}`
    : rawTitle;

  const baseDesc = task.description ? String(task.description).trim() : '';
  const description = isCompleted
    ? (baseDesc ? `${baseDesc}\n\n[Completed in Eleven11]` : '[Completed in Eleven11]')
    : baseDesc;

  const reminder = Number.isInteger(task.reminder_minutes)
    ? task.reminder_minutes
    : defaultReminderMinutes;

  return {
    summary,
    description,
    start: { dateTime: startLocal, timeZone: tz },
    end: { dateTime: endLocal, timeZone: tz },
    reminders: {
      useDefault: false,
      overrides: reminder > 0 ? [{ method: 'popup', minutes: reminder }] : [],
    },
  };
}

export async function syncTaskToGoogle(db, userId, taskData, config) {
  requireDatabase(db);
  if (!isUuid(userId)) throw httpError('Invalid user ID.', 400);
  if (!taskData || !isUuid(taskData.id)) throw httpError('Invalid task ID.', 400);
  if (!taskData.due_date || !taskData.due_time) {
    return { synced: false, reason: 'missing_date_or_time' };
  }

  const settings = await getTaskSyncSettings(db, userId);
  if (!settings.connected || !settings.autoTaskSync) {
    return { synced: false, reason: 'disabled_or_disconnected' };
  }

  const calendarId = taskData.google_calendar_id || settings.selectedCalendarId || 'primary';
  const eventId = taskData.google_event_id || uuidToGoogleEventId(taskData.id);
  const requestBody = buildTaskEventBody(taskData, settings.defaultReminderMinutes);

  const oauth = await getAuthenticatedGoogleClient(db, userId, config);
  try {
    const calendar = makeCalendarClient(oauth, config);
    let googleRes;
    if (taskData.google_event_id) {
      googleRes = await calendar.events.patch({
        calendarId,
        eventId,
        requestBody,
      });
    } else {
      try {
        googleRes = await calendar.events.insert({
          calendarId,
          requestBody: { id: eventId, ...requestBody },
        });
      } catch (err) {
        if (err?.code === 409 || err?.status === 409) {
          googleRes = await calendar.events.patch({
            calendarId,
            eventId,
            requestBody,
          });
        } else {
          throw err;
        }
      }
    }

    const savedEventId = googleRes.data?.id || eventId;
    await db.query(
      `UPDATE public.tasks
       SET google_calendar_id = $3,
           google_event_id = $4,
           google_sync_status = 'synced',
           updated_at = now()
       WHERE id = $1 AND user_id = $2`,
      [taskData.id, userId, calendarId, savedEventId],
    );

    return { synced: true, calendarId, eventId: savedEventId };
  } finally {
    await flushGoogleTokenWrites(oauth);
  }
}

export async function deleteTaskFromGoogle(db, userId, taskData, config) {
  requireDatabase(db);
  if (!isUuid(userId)) throw httpError('Invalid user ID.', 400);
  const eventId = taskData?.google_event_id;
  const calendarId = taskData?.google_calendar_id || 'primary';
  if (!eventId) return { deleted: false, reason: 'no_google_event' };

  const oauth = await getAuthenticatedGoogleClient(db, userId, config);
  try {
    const calendar = makeCalendarClient(oauth, config);
    try {
      await calendar.events.delete({ calendarId, eventId });
    } catch (err) {
      if (err?.code !== 404 && err?.code !== 410 && err?.status !== 404 && err?.status !== 410) {
        throw err;
      }
    }
    return { deleted: true, calendarId, eventId };
  } finally {
    await flushGoogleTokenWrites(oauth);
  }
}
