import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createRequireCalendarAuth } from '../src/calendar_auth.js';

function mockResponse() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
  return res;
}

function mockRequest(authHeader) {
  return {
    headers: {
      authorization: authHeader,
    },
    get(name) {
      return this.headers[name.toLowerCase()];
    },
  };
}

function requestError(res, status, message) {
  return res.status(status).json({ error: message });
}

test('requireCalendarAuth: rejects missing or non-bearer header with 401', async () => {
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {},
    findSession: async () => null,
    pgPool: null,
    requestError,
  });

  const res1 = mockResponse();
  const result1 = await requireCalendarAuth(mockRequest(undefined), res1);
  assert.equal(result1, null);
  assert.equal(res1.statusCode, 401);

  const res2 = mockResponse();
  const result2 = await requireCalendarAuth(mockRequest('Basic 12345'), res2);
  assert.equal(result2, null);
  assert.equal(res2.statusCode, 401);
});

test('requireCalendarAuth: authenticates valid Supabase JWT and extracts verified user UUID', async () => {
  const verifiedUuid = '11111111-2222-3333-4444-555555555555';
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {
      auth: {
        getUser: async (token) => {
          assert.equal(token, 'valid.supabase.jwt');
          return { data: { user: { id: verifiedUuid } }, error: null };
        },
      },
    },
    findSession: async () => null,
    pgPool: null,
    requestError,
  });

  const res = mockResponse();
  const req = mockRequest('Bearer valid.supabase.jwt');
  const session = await requireCalendarAuth(req, res);
  assert.ok(session);
  assert.equal(session.userId, verifiedUuid);
  assert.equal(session.authType, 'supabase_jwt');
  assert.equal(res.statusCode, 200);
});

test('requireCalendarAuth: rejects invalid or expired Supabase JWT with 401', async () => {
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {
      auth: {
        getUser: async () => ({
          data: null,
          error: new Error('jwt expired'),
        }),
      },
    },
    findSession: async () => null,
    pgPool: null,
    requestError,
  });

  const res = mockResponse();
  const req = mockRequest('Bearer expired.supabase.jwt');
  const session = await requireCalendarAuth(req, res);
  assert.equal(session, null);
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.body, { error: 'Your session has expired. Please sign in.' });
});

test('requireCalendarAuth: returns 503 on Supabase service failure without exposing error details', async () => {
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {
      auth: {
        getUser: async () => {
          throw new Error('Supabase network down or timeout');
        },
      },
    },
    findSession: async () => null,
    pgPool: null,
    requestError,
  });

  const res = mockResponse();
  const req = mockRequest('Bearer servererror.supabase.jwt');
  const session = await requireCalendarAuth(req, res);
  assert.equal(session, null);
  assert.equal(res.statusCode, 503);
  assert.deepEqual(res.body, { error: 'Authentication service temporarily unavailable.' });
});

test('requireCalendarAuth: authenticates legacy opaque session if profile exists in profiles table', async () => {
  const userId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {},
    findSession: async (token) => {
      assert.equal(token, 'opaqueTokenWithoutDots123456789012345678901234');
      return { id: 'session-id', userId };
    },
    pgPool: {
      query: async (sql, params) => {
        assert.ok(sql.includes('public.profiles'));
        assert.equal(params[0], userId);
        return { rows: [{ id: userId }] };
      },
    },
    requestError,
  });

  const res = mockResponse();
  const req = mockRequest('Bearer opaqueTokenWithoutDots123456789012345678901234');
  const session = await requireCalendarAuth(req, res);
  assert.ok(session);
  assert.equal(session.userId, userId);
  assert.equal(session.authType, 'legacy_session');
});

test('requireCalendarAuth: rejects legacy session if profile mapping does not exist in profiles table', async () => {
  const userId = 'unmapped-legacy-account-id';
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {},
    findSession: async () => ({ id: 'session-id', userId }),
    pgPool: {
      query: async () => ({ rows: [] }), // No matching profile
    },
    requestError,
  });

  const res = mockResponse();
  const req = mockRequest('Bearer opaqueTokenWithoutDots123456789012345678901234');
  const session = await requireCalendarAuth(req, res);
  assert.equal(session, null);
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.body, { error: 'User profile not found for this session.' });
});

test('requireCalendarAuth: legacy session returns 503 when admin.from(profiles) returns an error', async () => {
  const userId = 'user-with-db-error';
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {
      from: (table) => {
        assert.equal(table, 'profiles');
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: null,
                error: new Error('PostgREST connection error'),
              }),
            }),
          }),
        };
      },
    },
    findSession: async () => ({ id: 'session-id', userId }),
    pgPool: null, // Forces admin.from path
    requestError,
  });

  const res = mockResponse();
  const req = mockRequest('Bearer opaqueTokenWithoutDots123456789012345678901234');
  const session = await requireCalendarAuth(req, res);
  assert.equal(session, null);
  assert.equal(res.statusCode, 503);
  assert.deepEqual(res.body, { error: 'Authentication service temporarily unavailable.' });
});

test('requireCalendarAuth: legacy session returns 401 when admin.from(profiles) succeeds but returns no profile', async () => {
  const userId = 'unmapped-user-no-profile';
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {
      from: (table) => {
        assert.equal(table, 'profiles');
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: null,
                error: null,
              }),
            }),
          }),
        };
      },
    },
    findSession: async () => ({ id: 'session-id', userId }),
    pgPool: null, // Forces admin.from path
    requestError,
  });

  const res = mockResponse();
  const req = mockRequest('Bearer opaqueTokenWithoutDots123456789012345678901234');
  const session = await requireCalendarAuth(req, res);
  assert.equal(session, null);
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.body, { error: 'User profile not found for this session.' });
});

test('requireCalendarAuth: legacy session authenticates when admin.from(profiles) finds profile', async () => {
  const userId = 'mapped-user-with-profile';
  const requireCalendarAuth = createRequireCalendarAuth({
    admin: {
      from: (table) => {
        assert.equal(table, 'profiles');
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { id: userId },
                error: null,
              }),
            }),
          }),
        };
      },
    },
    findSession: async () => ({ id: 'session-id', userId }),
    pgPool: null, // Forces admin.from path
    requestError,
  });

  const res = mockResponse();
  const req = mockRequest('Bearer opaqueTokenWithoutDots123456789012345678901234');
  const session = await requireCalendarAuth(req, res);
  assert.ok(session);
  assert.equal(session.userId, userId);
  assert.equal(session.authType, 'legacy_session');
});
