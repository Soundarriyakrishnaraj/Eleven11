import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { randomBytes, randomUUID } from 'node:crypto';

import {
  decryptAes256Gcm,
  encryptAes256Gcm,
  parseAndValidateEncryptionKey,
  hashPassword,
  verifyPassword,
  validUsername,
  normalizeUsername,
  validEmail,
  normalizeEmail,
  validDateOfBirth,
  validatePassword,
  newOpaqueToken,
  sha256Hex,
  signDatabaseJwt,
} from '../src/security.js';

import {
  handleOAuthCallback,
  pullSyncGoogleCalendar,
  pushEventToGoogle,
  uuidToGoogleEventId,
} from '../src/google_calendar.js';

const TEST_KEY_HEX =
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const TEST_KEY = parseAndValidateEncryptionKey(TEST_KEY_HEX);

const USER_ID = '944d1d1e-8488-465c-958a-b349d5579198';
const EVENT_ID = 'a44d1d1e-8488-465c-958a-b349d5579198';

function makeConfig(overrides = {}) {
  return {
    encryptionKey: TEST_KEY,
    googleClientId: 'test-client-id',
    googleClientSecret: 'test-client-secret',
    googleRedirectUri: 'http://localhost:3000/api/calendar/callback',
    ...overrides,
  };
}

function makeOAuthFactory({ getToken, userInfo } = {}) {
  return () => {
    const oauth = new EventEmitter();

    oauth.generateAuthUrl = () => 'https://accounts.google.test/authorize';
    oauth.setCredentials = () => { };
    oauth.getToken = getToken || (async () => ({
      tokens: {
        access_token: 'access-token',
        refresh_token: 'refresh-token',
        expiry_date: Date.now() + 3600000,
      },
    }));
    oauth.revokeCredentials = async () => { };

    oauth.userInfo = userInfo;

    return oauth;
  };
}

// -----------------------------------------------------------------------------
// AES-256-GCM
// -----------------------------------------------------------------------------

test('AES-256-GCM token encryption, decryption, and key validation', () => {
  assert.throws(
    () => parseAndValidateEncryptionKey(''),
    /required/,
  );

  assert.throws(
    () => parseAndValidateEncryptionKey('tooshort'),
    /32 bytes/,
  );

  assert.throws(
    () => parseAndValidateEncryptionKey('zz'.repeat(32)),
    /32 bytes/,
  );

  const token = 'test-google-access-token';
  const encrypted = encryptAes256Gcm(token, TEST_KEY);

  assert.equal(typeof encrypted, 'string');
  assert.equal(encrypted.split(':').length, 3);
  assert.equal(decryptAes256Gcm(encrypted, TEST_KEY), token);

  const parts = encrypted.split(':');
  const tampered = `${parts[0]}:${parts[1]}:${parts[2].slice(0, -2)}aa`;

  assert.throws(() => decryptAes256Gcm(tampered, TEST_KEY));

  const wrongKey = parseAndValidateEncryptionKey(
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
  );

  assert.throws(() => decryptAes256Gcm(encrypted, wrongKey));
});

// -----------------------------------------------------------------------------
// Google event ID
// -----------------------------------------------------------------------------

test('UUID to Google Event ID deterministic conversion', () => {
  const result = uuidToGoogleEventId(USER_ID);

  assert.equal(result, 'el944d1d1e8488465c958ab349d5579198');
  assert.match(result, /^[a-v0-9]{5,1024}$/);

  assert.throws(
    () => uuidToGoogleEventId('not-a-uuid'),
    (error) => error.status === 400,
  );
});

// -----------------------------------------------------------------------------
// OAuth state replay protection
// -----------------------------------------------------------------------------

test('OAuth state is consumed once and cannot be replayed', async () => {
  const stateToken = randomBytes(32).toString('hex');
  let stateUsed = false;

  const mockDb = {
    query: async (sql, params) => {
      if (sql.includes('UPDATE public.google_oauth_states')) {
        if (params[0] === stateToken && !stateUsed) {
          stateUsed = true;

          return {
            rows: [{
              user_id: USER_ID,
              encrypted_code_verifier: encryptAes256Gcm(
                'sample-verifier',
                TEST_KEY,
              ),
            }],
          };
        }

        return { rows: [] };
      }

      return { rows: [] };
    },

    connect: async () => {
      throw new Error('Unexpected connect call');
    },
  };

  const config = makeConfig({
    oauth2ClientFactory: makeOAuthFactory({
      getToken: async () => {
        throw new Error('Google token exchange failed');
      },
    }),
  });

  await assert.rejects(
    () => handleOAuthCallback(
      mockDb,
      'invalid-code',
      stateToken,
      config,
    ),
    (error) => {
      assert.equal(error.status, 400);
      assert.match(error.message, /Failed to exchange code/);
      return true;
    },
  );

  await assert.rejects(
    () => handleOAuthCallback(
      mockDb,
      'another-code',
      stateToken,
      config,
    ),
    (error) => {
      assert.equal(error.status, 400);
      assert.match(error.message, /OAuth state is invalid/);
      return true;
    },
  );
});

// -----------------------------------------------------------------------------
// Lease ownership
// -----------------------------------------------------------------------------

test('Active event lease rejects a concurrent worker with HTTP 409', async () => {
  const idempotencyKey = randomUUID();
  const leaseOwner = randomUUID();

  const mockClient = {
    query: async (sql) => {
      if (sql === 'BEGIN') return { rows: [] };
      if (sql === 'ROLLBACK') return { rows: [] };

      if (sql.includes('SELECT *') && sql.includes('idempotency_key')) {
        return {
          rows: [{
            id: EVENT_ID,
            idempotency_key: idempotencyKey,
            sync_status: 'syncing',
            sync_lease_owner: leaseOwner,
            sync_lease_until: new Date(Date.now() + 30000),
          }],
        };
      }

      throw new Error(`Unexpected SQL in lease test: ${sql}`);
    },

    release() { },
  };

  const mockDb = {
    query: async () => ({ rows: [] }),
    connect: async () => mockClient,
  };

  const config = makeConfig();

  await assert.rejects(
    () => pushEventToGoogle(
      mockDb,
      USER_ID,
      {
        id: EVENT_ID,
        idempotencyKey,
        title: 'Concurrent Meeting',
        startTime: '2026-11-25T10:00:00Z',
        endTime: '2026-11-25T11:00:00Z',
      },
      config,
    ),
    (error) => {
      assert.equal(error.status, 409);
      assert.match(error.message, /Operation in progress/);
      return true;
    },
  );
});

// -----------------------------------------------------------------------------
// Sync rollback
// -----------------------------------------------------------------------------

test('Sync preserves previous token when event processing fails', async () => {
  let rolledBack = false;
  let committed = false;
  let tokenUpdated = false;
  let released = false;

  const oldSyncToken = 'existing-sync-token';
  const lockKey = 'test-lock';

  const oauthFactory = () => {
    const oauth = new EventEmitter();
    oauth.setCredentials = () => { };
    return oauth;
  };

  const mockClient = {
    query: async (sql, params = []) => {
      if (sql.includes('pg_try_advisory_lock')) {
        assert.equal(params[0], `eleven11-google-calendar:${USER_ID}`);
        return { rows: [{ locked: true }] };
      }

      if (sql.includes('SELECT encrypted_access_token')) {
        return {
          rows: [{
            encrypted_access_token: encryptAes256Gcm('access', TEST_KEY),
            encrypted_refresh_token: encryptAes256Gcm('refresh', TEST_KEY),
            token_expires_at: new Date(Date.now() + 3600000),
          }],
        };
      }

      if (sql.includes('SELECT next_sync_token')) {
        return { rows: [{ next_sync_token: oldSyncToken }] };
      }

      if (sql === 'BEGIN') return { rows: [] };

      if (sql === 'COMMIT') {
        committed = true;
        return { rows: [] };
      }

      if (sql === 'ROLLBACK') {
        rolledBack = true;
        return { rows: [] };
      }

      if (sql.includes('UPDATE public.user_google_calendar_tokens') &&
        sql.includes('next_sync_token = $1')) {
        tokenUpdated = true;
        return { rows: [] };
      }

      if (sql.includes('pg_advisory_unlock')) {
        return { rows: [{ unlocked: true }] };
      }

      throw new Error(`Unexpected SQL in sync test: ${sql}`);
    },

    release() {
      released = true;
    },
  };

  const mockPool = {
    query: async () => ({ rows: [] }),
    connect: async () => mockClient,
  };

  const config = makeConfig({
    oauth2ClientFactory: oauthFactory,

    calendarClientFactory: () => ({
      events: {
        list: async () => ({
          data: {
            items: [{
              id: 'bad-google-event',
              status: 'confirmed',
              summary: 'Malformed event',
              // Deliberately missing start and end.
            }],
            nextSyncToken: 'new-sync-token',
          },
        }),
      },
    }),
  });

  await assert.rejects(
    () => pullSyncGoogleCalendar(mockPool, USER_ID, config),
    /invalid start or end/i,
  );

  assert.equal(rolledBack, true);
  assert.equal(committed, false);
  assert.equal(tokenUpdated, false);
  assert.equal(released, true);
});

// -----------------------------------------------------------------------------
// Full sync must not prune local Eleven11 events
// -----------------------------------------------------------------------------

test('Full sync does not run destructive event pruning', async () => {
  const executedSql = [];

  const mockClient = {
    query: async (sql, params = []) => {
      executedSql.push(sql);

      if (sql.includes('pg_try_advisory_lock')) {
        return { rows: [{ locked: true }] };
      }

      if (sql.includes('SELECT encrypted_access_token')) {
        return {
          rows: [{
            encrypted_access_token: encryptAes256Gcm('access', TEST_KEY),
            encrypted_refresh_token: encryptAes256Gcm('refresh', TEST_KEY),
            token_expires_at: new Date(Date.now() + 3600000),
          }],
        };
      }

      if (sql.includes('SELECT next_sync_token')) {
        return { rows: [{ next_sync_token: null }] };
      }

      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
        return { rows: [] };
      }

      if (sql.includes('UPDATE public.user_google_calendar_tokens') &&
        sql.includes('next_sync_token = $1')) {
        return { rows: [] };
      }

      if (sql.includes('pg_advisory_unlock')) {
        return { rows: [{ unlocked: true }] };
      }

      throw new Error(`Unexpected SQL in full-sync test: ${sql}`);
    },

    release() { },
  };

  const mockPool = {
    query: async () => ({ rows: [] }),
    connect: async () => mockClient,
  };

  const config = makeConfig({
    oauth2ClientFactory: makeOAuthFactory(),

    calendarClientFactory: () => ({
      events: {
        list: async () => ({
          data: {
            items: [],
            nextSyncToken: 'first-sync-token',
          },
        }),
      },
    }),
  });

  const result = await pullSyncGoogleCalendar(
    mockPool,
    USER_ID,
    config,
  );

  assert.equal(result.success, true);
  assert.equal(result.fullSync, true);

  const destructivePrune = executedSql.some((sql) =>
    sql.includes('NOT (google_event_id = ANY'),
  );

  assert.equal(destructivePrune, false);
});

// -----------------------------------------------------------------------------
// Authentication and utility tests
// -----------------------------------------------------------------------------

test('Username validation and normalization', () => {
  assert.equal(validUsername('Eleven_User'), true);
  assert.equal(validUsername('ab'), false);
  assert.equal(normalizeUsername('  ELEVEN_User  '), 'eleven_user');
});

test('Email validation and normalization', () => {
  assert.equal(validEmail('test@example.com'), true);
  assert.equal(validEmail('not-an-email'), false);
  assert.equal(normalizeEmail(' TEST@Example.COM '), 'test@example.com');
});

test('Date of Birth validation', () => {
  assert.equal(validDateOfBirth('2000-01-01'), true);
  assert.equal(validDateOfBirth('2025-02-31'), false);
  assert.equal(validDateOfBirth('not-a-date'), false);
});

test('Password policy validation', () => {
  assert.equal(validatePassword('StrongPass1!'), null);
  assert.notEqual(validatePassword('weak'), null);
});

test('Argon2id password hashing and verification', async () => {
  const password = 'StrongPass1!';
  const hash = await hashPassword(password);

  assert.match(hash, /^\$argon2id\$/);
  assert.equal(await verifyPassword(password, hash), true);
  assert.equal(await verifyPassword('wrong-password', hash), false);
});

test('Safe handling of missing or placeholder hashes', async () => {
  assert.equal(await verifyPassword('password', ''), false);
  assert.equal(await verifyPassword('password', null), false);
  assert.equal(await verifyPassword('password', '!disabled'), false);
  assert.equal(
    await verifyPassword('password', 'legacy_placeholder'),
    false,
  );
});

test('Opaque token and SHA-256 hashing', () => {
  const token = newOpaqueToken();

  assert.equal(typeof token, 'string');
  assert.ok(token.length > 20);
  assert.equal(sha256Hex('test').length, 64);
});

test('Short-lived database JWT generation', () => {
  const jwt = signDatabaseJwt({
    userId: USER_ID,
    sessionId: randomUUID(),
    email: 'test@example.com',
    secret: 'test-secret-for-unit-tests',
    expiresInSeconds: 60,
  });

  assert.equal(jwt.split('.').length, 3);
});
