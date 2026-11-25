import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAdminHandlers } from '../src/admin_api.js';

const DESIGNATED_ADMIN_UUID = '74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a';
const PROMOTED_ADMIN_UUID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const USER_A_UUID = '11111111-2222-3333-4444-555555555555';
const USER_B_UUID = '66666666-7777-8888-9999-aaaaaaaaaaaa';
const FEEDBACK_ID = '99999999-8888-7777-6666-555555555555';

function makeMockRes() {
  return {
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
}

function requestError(res, status, message) {
  return res.status(status).json({ error: message });
}

/**
 * In-memory stateful PostgreSQL pool simulator for end-to-end multi-user admin testing.
 */
function createInMemoryDb({ withMigration016 = true } = {}) {
  const now = new Date();
  const state = {
    profiles: [
      {
        id: DESIGNATED_ADMIN_UUID,
        username: 'admin_main',
        full_name: 'Main Admin',
        tz: 'Asia/Kolkata',
        created_at: new Date(now.getTime() - 20 * 24 * 60 * 60 * 1000).toISOString(),
        updated_at: now.toISOString(),
        deleted_at: null,
      },
      {
        id: USER_A_UUID,
        username: 'alice_dev',
        full_name: 'Alice Developer',
        tz: 'UTC',
        created_at: new Date(now.getTime() - 2 * 24 * 60 * 60 * 1000).toISOString(),
        updated_at: now.toISOString(),
        deleted_at: null,
      },
      {
        id: USER_B_UUID,
        username: 'bob_tester',
        full_name: 'Bob Tester',
        tz: 'America/New_York',
        created_at: now.toISOString(),
        updated_at: now.toISOString(),
        deleted_at: null,
      },
    ],
    adminRoles: [{ user_id: PROMOTED_ADMIN_UUID, role: 'super_admin' }],
    events: [],
    feedback: [],
    loginHistory: [],
    presence: new Map(),
    nextLoginId: 1,
  };

  const pgPool = {
    async query(sql, params = []) {
      const s = sql.replace(/\s+/g, ' ').trim();

      if (s.includes('FROM public.admin_roles')) {
        const match = state.adminRoles.filter(
          (r) => r.user_id === params[0] && ['admin', 'super_admin'].includes(r.role),
        );
        return { rows: match, rowCount: match.length };
      }

      if (s.includes('public.user_activity_presence')) {
        if (!withMigration016) {
          const err = new Error('relation "public.user_activity_presence" does not exist');
          err.code = '42P01';
          throw err;
        }
        if (s.startsWith('INSERT INTO public.user_activity_presence')) {
          const [userId, ts, appVersion] = params;
          const prev = state.presence.get(userId) || {};
          state.presence.set(userId, {
            user_id: userId,
            last_active_at: ts,
            last_login_at: s.includes('last_login_at') ? ts : prev.last_login_at ?? null,
            app_version: appVersion ?? prev.app_version ?? null,
          });
          return { rows: [], rowCount: 1 };
        }
        if (s.includes('ANY($1::uuid[])')) {
          const ids = params[0];
          const rows = ids
            .map((id) => state.presence.get(id))
            .filter(Boolean);
          return { rows, rowCount: rows.length };
        }
        // Metrics aggregate
        const [t15, tToday, t7d, t30d] = params.map((p) => Date.parse(p));
        const all = [...state.presence.values()];
        return {
          rows: [
            {
              active_15m: all.filter((p) => Date.parse(p.last_active_at) >= t15).length,
              dau: all.filter((p) => Date.parse(p.last_active_at) >= tToday).length,
              wau: all.filter((p) => Date.parse(p.last_active_at) >= t7d).length,
              mau: all.filter((p) => Date.parse(p.last_active_at) >= t30d).length,
            },
          ],
          rowCount: 1,
        };
      }

      if (s.includes('public.login_history')) {
        if (!withMigration016) {
          const err = new Error('relation "public.login_history" does not exist');
          err.code = '42P01';
          throw err;
        }
        if (s.startsWith('INSERT INTO public.login_history')) {
          const [userId, eventType, ts, appVersion] = params;
          state.loginHistory.push({
            id: state.nextLoginId++,
            user_id: userId,
            event_type: eventType,
            occurred_at: ts,
            app_version: appVersion,
          });
          return { rows: [], rowCount: 1 };
        }
        if (s.includes('WHERE user_id = $1')) {
          const [userId, limit] = params;
          const rows = state.loginHistory
            .filter((e) => e.user_id === userId)
            .sort((a, b) => Date.parse(b.occurred_at) - Date.parse(a.occurred_at) || b.id - a.id)
            .slice(0, limit);
          return { rows, rowCount: rows.length };
        }
        return {
          rows: [
            {
              logins: state.loginHistory.filter((e) => e.event_type === 'login').length,
              logouts: state.loginHistory.filter((e) => e.event_type === 'logout').length,
              expiries: state.loginHistory.filter((e) => e.event_type === 'session_expired').length,
            },
          ],
          rowCount: 1,
        };
      }

      if (s.includes('FROM public.events')) {
        return { rows: [{ count: state.events.length }], rowCount: 1 };
      }

      if (s.includes('public.user_feedback')) {
        if (s.startsWith('SELECT COUNT(*)')) {
          return { rows: [{ count: state.feedback.length }], rowCount: 1 };
        }
        if (s.startsWith('UPDATE public.user_feedback')) {
          const [status, hasNote, note, id] = params;
          const item = state.feedback.find((f) => f.id === id);
          if (!item) return { rows: [], rowCount: 0 };
          if (status) item.status = status;
          if (hasNote) item.admin_note = note;
          item.updated_at = new Date().toISOString();
          return { rows: [item], rowCount: 1 };
        }
        // SELECT feedback joined with profiles
        let rows = state.feedback.map((f) => {
          const p = state.profiles.find((u) => u.id === f.user_id);
          return { ...f, username: p?.username ?? null, full_name: p?.full_name ?? null };
        });
        if (s.includes('WHERE f.status = $1')) {
          rows = rows.filter((r) => r.status === params[0]);
        }
        return { rows, rowCount: rows.length };
      }

      if (s.includes('FROM public.profiles')) {
        let active = state.profiles.filter((p) => p.deleted_at === null);
        if (s.includes('FILTER (WHERE created_at')) {
          const [tToday, tWeek, tMonth] = params.map((p) => Date.parse(p));
          return {
            rows: [
              {
                today: active.filter((p) => Date.parse(p.created_at) >= tToday).length,
                this_week: active.filter((p) => Date.parse(p.created_at) >= tWeek).length,
                this_month: active.filter((p) => Date.parse(p.created_at) >= tMonth).length,
              },
            ],
            rowCount: 1,
          };
        }
        if (s.includes('LIKE $1')) {
          const needle = params[0].replace(/%/g, '').toLowerCase();
          active = active.filter(
            (p) =>
              (p.username ?? '').toLowerCase().includes(needle) ||
              (p.full_name ?? '').toLowerCase().includes(needle) ||
              p.id.toLowerCase().includes(needle),
          );
        }
        if (s.startsWith('SELECT COUNT(DISTINCT id)')) {
          return { rows: [{ count: active.length }], rowCount: 1 };
        }
        const limit = params[params.length - 2];
        const offset = params[params.length - 1];
        const sorted = [...active].sort(
          (a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || a.id.localeCompare(b.id),
        );
        return {
          rows: sorted.slice(offset, offset + limit),
          rowCount: sorted.slice(offset, offset + limit).length,
        };
      }

      throw new Error(`Unhandled SQL in test double: ${s}`);
    },
  };

  return { state, pgPool };
}

function makeAuthResolver(userMap) {
  return async (req, res) => {
    const auth = req.headers?.authorization ?? '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
    if (!token || !userMap[token]) {
      requestError(res, 401, 'Authentication required.');
      return null;
    }
    return { userId: userMap[token], authType: 'supabase_jwt' };
  };
}

test('Admin API Authorization & Security (real handlers)', async (t) => {
  const { pgPool } = createInMemoryDb({ withMigration016: true });
  const handlers = createAdminHandlers({
    requireAuth: makeAuthResolver({
      'admin-jwt': DESIGNATED_ADMIN_UUID,
      'promoted-jwt': PROMOTED_ADMIN_UUID,
      'user-a-jwt': USER_A_UUID,
    }),
    admin: null,
    pgPool,
    requestError,
    designatedAdminUuid: DESIGNATED_ADMIN_UUID,
  });

  await t.test('1. Unauthenticated requests are rejected with 401 across all admin endpoints', async () => {
    for (const [fn, req] of [
      [handlers.getMetrics, { headers: {} }],
      [handlers.getUsers, { headers: {}, query: {} }],
      [handlers.getUserActivity, { headers: {}, params: { userId: USER_A_UUID }, query: {} }],
      [handlers.getFeedback, { headers: {}, query: {} }],
      [handlers.patchFeedback, { headers: {}, params: { id: FEEDBACK_ID }, body: { status: 'resolved' } }],
    ]) {
      const res = makeMockRes();
      await fn(req, res);
      assert.equal(res.statusCode, 401);
    }
  });

  await t.test('2. Ordinary authenticated users are rejected with 403 Forbidden', async () => {
    for (const [fn, req] of [
      [handlers.getMetrics, { headers: { authorization: 'Bearer user-a-jwt' } }],
      [handlers.getUsers, { headers: { authorization: 'Bearer user-a-jwt' }, query: {} }],
      [handlers.getUserActivity, { headers: { authorization: 'Bearer user-a-jwt' }, params: { userId: USER_B_UUID }, query: {} }],
      [handlers.getFeedback, { headers: { authorization: 'Bearer user-a-jwt' }, query: {} }],
      [handlers.patchFeedback, { headers: { authorization: 'Bearer user-a-jwt' }, params: { id: FEEDBACK_ID }, body: { status: 'resolved' } }],
    ]) {
      const res = makeMockRes();
      await fn(req, res);
      assert.equal(res.statusCode, 403);
    }
  });

  await t.test('3. Designated admin UUID and promoted super_admin role are granted access', async () => {
    const res1 = makeMockRes();
    await handlers.getMetrics({ headers: { authorization: 'Bearer admin-jwt' } }, res1);
    assert.equal(res1.statusCode, 200);
    assert.equal(res1.body.totalUsers, 3);

    const res2 = makeMockRes();
    await handlers.getMetrics({ headers: { authorization: 'Bearer promoted-jwt' } }, res2);
    assert.equal(res2.statusCode, 200);
    assert.equal(res2.body.totalUsers, 3);
  });

  await t.test('4. Invalid feedback updates and immutable field tampering are rejected with 400', async () => {
    const resBadStatus = makeMockRes();
    await handlers.patchFeedback(
      {
        headers: { authorization: 'Bearer admin-jwt' },
        params: { id: FEEDBACK_ID },
        body: { status: 'hacked_status' },
      },
      resBadStatus,
    );
    assert.equal(resBadStatus.statusCode, 400);

    const resImmutable = makeMockRes();
    await handlers.patchFeedback(
      {
        headers: { authorization: 'Bearer admin-jwt' },
        params: { id: FEEDBACK_ID },
        body: { status: 'reviewed', message: 'tampered' },
      },
      resImmutable,
    );
    assert.equal(resImmutable.statusCode, 400);
    assert.match(resImmutable.body.error, /immutable/i);

    const resEmpty = makeMockRes();
    await handlers.patchFeedback(
      {
        headers: { authorization: 'Bearer admin-jwt' },
        params: { id: FEEDBACK_ID },
        body: {},
      },
      resEmpty,
    );
    assert.equal(resEmpty.statusCode, 400);
  });
});

test('Multi-User Lifecycle: Unique Users, Login/Logout/Expiry History, Live Metrics, and Feedback Delivery', async () => {
  const { state, pgPool } = createInMemoryDb({ withMigration016: true });
  const handlers = createAdminHandlers({
    requireAuth: makeAuthResolver({
      'admin-jwt': DESIGNATED_ADMIN_UUID,
      'user-a-jwt': USER_A_UUID,
      'user-b-jwt': USER_B_UUID,
    }),
    admin: null,
    pgPool,
    requestError,
    designatedAdminUuid: DESIGNATED_ADMIN_UUID,
  });

  // Step 1: Initial metrics before any user activity — ZERO fabricated numbers!
  const initialRes = makeMockRes();
  await handlers.getMetrics({ headers: { authorization: 'Bearer admin-jwt' } }, initialRes);
  assert.equal(initialRes.statusCode, 200);
  assert.equal(initialRes.body.totalUsers, 3);
  assert.equal(initialRes.body.totalEvents, 0);
  assert.equal(initialRes.body.totalFeedback, 0);
  assert.equal(initialRes.body.activity.activeLast15Min, 0);
  assert.equal(initialRes.body.activity.dau, 0);
  assert.equal(initialRes.body.activity.totalLogins, 0);

  // Step 2: Unique users pagination & search (all 3 users returned, never silently dropped)
  const page1 = makeMockRes();
  await handlers.getUsers(
    { headers: { authorization: 'Bearer admin-jwt' }, query: { page: '1', limit: '2' } },
    page1,
  );
  assert.equal(page1.statusCode, 200);
  assert.equal(page1.body.total, 3);
  assert.equal(page1.body.users.length, 2);
  assert.equal(page1.body.hasMore, true);

  const page2 = makeMockRes();
  await handlers.getUsers(
    { headers: { authorization: 'Bearer admin-jwt' }, query: { page: '2', limit: '2' } },
    page2,
  );
  assert.equal(page2.body.users.length, 1);
  assert.equal(page2.body.hasMore, false);

  const allIds = [...page1.body.users, ...page2.body.users].map((u) => u.id);
  assert.equal(new Set(allIds).size, 3, 'Every registered user appears exactly once');

  // Search by username, full_name, and UUID
  const searchRes = makeMockRes();
  await handlers.getUsers(
    { headers: { authorization: 'Bearer admin-jwt' }, query: { q: 'alice' } },
    searchRes,
  );
  assert.equal(searchRes.body.users.length, 1);
  assert.equal(searchRes.body.users[0].id, USER_A_UUID);

  // Step 3: User A logs in, creates an event, submits feedback, and logs out
  const loginARes = makeMockRes();
  await handlers.recordAuthEvent(
    { headers: { authorization: 'Bearer user-a-jwt' }, body: { event_type: 'login', app_version: '1.0.0+1' } },
    loginARes,
  );
  assert.equal(loginARes.statusCode, 201);
  assert.equal(loginARes.body.user_id, USER_A_UUID);

  state.events.push({ id: 'evt-1', user_id: USER_A_UUID, title: 'Morning Focus' });
  state.feedback.push({
    id: FEEDBACK_ID,
    user_id: USER_A_UUID,
    message: 'Bug report from Alice',
    rating: 4,
    category: 'bug_report',
    status: 'new',
    admin_note: null,
    created_at: new Date().toISOString(),
    updated_at: null,
  });

  const logoutARes = makeMockRes();
  await handlers.recordAuthEvent(
    { headers: { authorization: 'Bearer user-a-jwt' }, body: { event_type: 'logout', app_version: '1.0.0+1' } },
    logoutARes,
  );
  assert.equal(logoutARes.statusCode, 201);

  // Step 4: User B logs in and then experiences session_expired (not fabricated logout)
  const loginBRes = makeMockRes();
  await handlers.recordAuthEvent(
    { headers: { authorization: 'Bearer user-b-jwt' }, body: { event_type: 'login' } },
    loginBRes,
  );
  assert.equal(loginBRes.statusCode, 201);

  const expireBRes = makeMockRes();
  await handlers.recordAuthEvent(
    { headers: { authorization: 'Bearer user-b-jwt' }, body: { event_type: 'session_expired' } },
    expireBRes,
  );
  assert.equal(expireBRes.statusCode, 201);

  // Step 5: Verify Admin Metrics reflect exact live changes
  const afterRes = makeMockRes();
  await handlers.getMetrics({ headers: { authorization: 'Bearer admin-jwt' } }, afterRes);
  assert.equal(afterRes.statusCode, 200);
  assert.equal(afterRes.body.totalUsers, 3);
  assert.equal(afterRes.body.totalEvents, 1);
  assert.equal(afterRes.body.totalFeedback, 1);
  assert.equal(afterRes.body.activity.activeLast15Min, 2);
  assert.equal(afterRes.body.activity.dau, 2);
  assert.equal(afterRes.body.activity.totalLogins, 2);
  assert.equal(afterRes.body.activity.totalLogouts, 1);
  assert.equal(afterRes.body.activity.totalSessionExpiries, 1);

  // Step 6: Verify chronological activity history per user
  const actA = makeMockRes();
  await handlers.getUserActivity(
    { headers: { authorization: 'Bearer admin-jwt' }, params: { userId: USER_A_UUID }, query: {} },
    actA,
  );
  assert.equal(actA.statusCode, 200);
  assert.equal(actA.body.events.length, 2);
  assert.equal(actA.body.events[0].event_type, 'logout');
  assert.equal(actA.body.events[1].event_type, 'login');

  const actB = makeMockRes();
  await handlers.getUserActivity(
    { headers: { authorization: 'Bearer admin-jwt' }, params: { userId: USER_B_UUID }, query: {} },
    actB,
  );
  assert.equal(actB.body.events.length, 2);
  assert.equal(actB.body.events[0].event_type, 'session_expired');
  assert.equal(actB.body.events[1].event_type, 'login');

  // Step 7: Verify Feedback Inbox & Triage
  const fbRes = makeMockRes();
  await handlers.getFeedback(
    { headers: { authorization: 'Bearer admin-jwt' }, query: { status: 'new' } },
    fbRes,
  );
  assert.equal(fbRes.statusCode, 200);
  assert.equal(fbRes.body.feedback.length, 1);
  assert.equal(fbRes.body.feedback[0].user_id, USER_A_UUID);
  assert.equal(fbRes.body.feedback[0].username, 'alice_dev');

  const triageRes = makeMockRes();
  await handlers.patchFeedback(
    {
      headers: { authorization: 'Bearer admin-jwt' },
      params: { id: FEEDBACK_ID },
      body: { status: 'resolved', admin_note: 'Fixed in release' },
    },
    triageRes,
  );
  assert.equal(triageRes.statusCode, 200);
  assert.equal(triageRes.body.feedback.status, 'resolved');
  assert.equal(triageRes.body.feedback.admin_note, 'Fixed in release');
});

test('Graceful behavior when Migration 016 is not yet applied (no fabricated metrics)', async () => {
  const { pgPool } = createInMemoryDb({ withMigration016: false });
  const handlers = createAdminHandlers({
    requireAuth: makeAuthResolver({ 'admin-jwt': DESIGNATED_ADMIN_UUID }),
    admin: null,
    pgPool,
    requestError,
    designatedAdminUuid: DESIGNATED_ADMIN_UUID,
  });

  const metricsRes = makeMockRes();
  await handlers.getMetrics({ headers: { authorization: 'Bearer admin-jwt' } }, metricsRes);
  assert.equal(metricsRes.statusCode, 200);
  assert.equal(metricsRes.body.totalUsers, 3);
  assert.equal(metricsRes.body.activity.presenceAvailable, false);
  assert.equal(metricsRes.body.activity.loginHistoryAvailable, false);
  assert.equal(metricsRes.body.activity.activeLast15Min, null);
  assert.equal(metricsRes.body.activity.dau, null);
  assert.equal(metricsRes.body.activity.wau, null);
  assert.equal(metricsRes.body.activity.mau, null);
  assert.equal(metricsRes.body.activity.totalLogins, null);

  const actRes = makeMockRes();
  await handlers.getUserActivity(
    { headers: { authorization: 'Bearer admin-jwt' }, params: { userId: USER_A_UUID }, query: {} },
    actRes,
  );
  assert.equal(actRes.statusCode, 200);
  assert.deepEqual(actRes.body.events, []);
  assert.equal(actRes.body.tableAvailable, false);
});
