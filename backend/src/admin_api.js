const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const VALID_FEEDBACK_STATUSES = ['new', 'reviewed', 'resolved', 'dismissed'];
const VALID_AUTH_EVENT_TYPES = ['login', 'logout', 'session_expired'];
const IMMUTABLE_FEEDBACK_FIELDS = ['user_id', 'message', 'rating', 'category', 'created_at'];

function isMissingRelationOrColumnError(err) {
  const code = err?.code ?? '';
  const msg = String(err?.message ?? '').toLowerCase();
  return (
    code === '42P01' ||
    code === '42703' ||
    code === 'PGRST205' ||
    code === 'PGRST204' ||
    msg.includes('does not exist') ||
    msg.includes('could not find the table') ||
    msg.includes('schema cache')
  );
}

export function createAdminHandlers({
  requireAuth,
  admin,
  pgPool,
  requestError,
  designatedAdminUuid = '74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a',
}) {
  if (typeof requireAuth !== 'function') {
    throw new TypeError('createAdminHandlers requires requireAuth.');
  }

  async function requireAdmin(request, response) {
    const session = await requireAuth(request, response);
    if (!session) return null;

    const userId = session.userId;
    if (!userId) {
      requestError(response, 401, 'Authentication required.');
      return null;
    }

    // 1. Designated super-admin UUID
    if (userId === designatedAdminUuid) {
      return session;
    }

    // 2. Authorized admin_roles record
    try {
      if (pgPool?.query) {
        const res = await pgPool.query(
          "SELECT role FROM public.admin_roles WHERE user_id = $1 AND role IN ('admin', 'super_admin') LIMIT 1",
          [userId],
        );
        if (res.rows.length > 0) {
          return session;
        }
      } else if (admin?.from) {
        const { data } = await admin
          .from('admin_roles')
          .select('role')
          .eq('user_id', userId)
          .in('role', ['admin', 'super_admin'])
          .maybeSingle();

        if (data) {
          return session;
        }
      }
    } catch (err) {
      console.error('Error verifying admin permissions:', err);
    }

    requestError(response, 403, 'Forbidden: Administrator privileges required.');
    return null;
  }

  // 1. GET /api/admin/metrics
  async function getMetrics(request, response) {
    const adminSession = await requireAdmin(request, response);
    if (!adminSession) return;

    try {
      let totalUsers = 0;
      let totalEvents = 0;
      let totalFeedback = 0;
      let registrationsToday = 0;
      let registrationsThisWeek = 0;
      let registrationsThisMonth = 0;

      // Presence & login metrics default to null (unknown/pending migration) — NEVER fabricated!
      let activeLast15Min = null;
      let dau = null;
      let wau = null;
      let mau = null;
      let totalLogins = null;
      let totalLogouts = null;
      let totalSessionExpiries = null;
      let presenceAvailable = false;
      let loginHistoryAvailable = false;

      const now = new Date();
      const todayStartIso = new Date(
        Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
      ).toISOString();
      const dayOfWeek = now.getUTCDay();
      const diffToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
      const weekStartIso = new Date(
        Date.UTC(
          now.getUTCFullYear(),
          now.getUTCMonth(),
          now.getUTCDate() - diffToMonday,
        ),
      ).toISOString();
      const monthStartIso = new Date(
        Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
      ).toISOString();
      const fifteenMinAgoIso = new Date(now.getTime() - 15 * 60 * 1000).toISOString();
      const sevenDaysAgoIso = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
      const thirtyDaysAgoIso = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

      if (pgPool?.query) {
        const usersRes = await pgPool.query(
          'SELECT COUNT(DISTINCT id)::int AS count FROM public.profiles WHERE deleted_at IS NULL',
        );
        totalUsers = usersRes.rows[0]?.count ?? 0;

        try {
          const eventsRes = await pgPool.query('SELECT COUNT(*)::int AS count FROM public.events');
          totalEvents = eventsRes.rows[0]?.count ?? 0;
        } catch (err) {
          if (!isMissingRelationOrColumnError(err)) throw err;
        }

        try {
          const fbRes = await pgPool.query('SELECT COUNT(*)::int AS count FROM public.user_feedback');
          totalFeedback = fbRes.rows[0]?.count ?? 0;
        } catch (err) {
          if (!isMissingRelationOrColumnError(err)) throw err;
        }

        const regRes = await pgPool.query(
          `SELECT
             COUNT(*) FILTER (WHERE created_at >= $1)::int AS today,
             COUNT(*) FILTER (WHERE created_at >= $2)::int AS this_week,
             COUNT(*) FILTER (WHERE created_at >= $3)::int AS this_month
           FROM public.profiles
           WHERE deleted_at IS NULL`,
          [todayStartIso, weekStartIso, monthStartIso],
        );
        registrationsToday = regRes.rows[0]?.today ?? 0;
        registrationsThisWeek = regRes.rows[0]?.this_week ?? 0;
        registrationsThisMonth = regRes.rows[0]?.this_month ?? 0;

        // Presence metrics (real DB values only)
        try {
          const presRes = await pgPool.query(
            `SELECT
               COUNT(DISTINCT user_id) FILTER (WHERE last_active_at >= $1)::int AS active_15m,
               COUNT(DISTINCT user_id) FILTER (WHERE last_active_at >= $2)::int AS dau,
               COUNT(DISTINCT user_id) FILTER (WHERE last_active_at >= $3)::int AS wau,
               COUNT(DISTINCT user_id) FILTER (WHERE last_active_at >= $4)::int AS mau
             FROM public.user_activity_presence`,
            [fifteenMinAgoIso, todayStartIso, sevenDaysAgoIso, thirtyDaysAgoIso],
          );
          activeLast15Min = presRes.rows[0]?.active_15m ?? 0;
          dau = presRes.rows[0]?.dau ?? 0;
          wau = presRes.rows[0]?.wau ?? 0;
          mau = presRes.rows[0]?.mau ?? 0;
          presenceAvailable = true;
        } catch (err) {
          if (!isMissingRelationOrColumnError(err)) throw err;
        }

        // Login/Logout/Session-Expiry metrics (real DB values only)
        try {
          const loginsRes = await pgPool.query(
            `SELECT
               COUNT(*) FILTER (WHERE event_type = 'login')::int AS logins,
               COUNT(*) FILTER (WHERE event_type = 'logout')::int AS logouts,
               COUNT(*) FILTER (WHERE event_type = 'session_expired')::int AS expiries
             FROM public.login_history`,
          );
          totalLogins = loginsRes.rows[0]?.logins ?? 0;
          totalLogouts = loginsRes.rows[0]?.logouts ?? 0;
          totalSessionExpiries = loginsRes.rows[0]?.expiries ?? 0;
          loginHistoryAvailable = true;
        } catch (err) {
          if (isMissingRelationOrColumnError(err)) {
            // Fallback if login_history exists without event_type column
            try {
              const basicRes = await pgPool.query(
                'SELECT COUNT(*)::int AS count FROM public.login_history',
              );
              totalLogins = basicRes.rows[0]?.count ?? 0;
              loginHistoryAvailable = true;
            } catch (innerErr) {
              if (!isMissingRelationOrColumnError(innerErr)) throw innerErr;
            }
          } else {
            throw err;
          }
        }
      } else {
        const { count: uCount, error: uErr } = await admin
          .from('profiles')
          .select('id', { count: 'exact', head: true })
          .is('deleted_at', null);
        if (uErr) throw uErr;
        totalUsers = uCount ?? 0;

        const { count: eCount, error: eErr } = await admin
          .from('events')
          .select('id', { count: 'exact', head: true });
        if (!eErr) totalEvents = eCount ?? 0;

        const { count: fCount, error: fErr } = await admin
          .from('user_feedback')
          .select('id', { count: 'exact', head: true });
        if (!fErr) totalFeedback = fCount ?? 0;

        const [tRes, wRes, mRes] = await Promise.all([
          admin
            .from('profiles')
            .select('id', { count: 'exact', head: true })
            .is('deleted_at', null)
            .gte('created_at', todayStartIso),
          admin
            .from('profiles')
            .select('id', { count: 'exact', head: true })
            .is('deleted_at', null)
            .gte('created_at', weekStartIso),
          admin
            .from('profiles')
            .select('id', { count: 'exact', head: true })
            .is('deleted_at', null)
            .gte('created_at', monthStartIso),
        ]);
        registrationsToday = tRes.count ?? 0;
        registrationsThisWeek = wRes.count ?? 0;
        registrationsThisMonth = mRes.count ?? 0;

        // Presence metrics via Supabase client
        const p15 = await admin
          .from('user_activity_presence')
          .select('user_id', { count: 'exact', head: true })
          .gte('last_active_at', fifteenMinAgoIso);
        if (!p15.error) {
          presenceAvailable = true;
          activeLast15Min = p15.count ?? 0;
          const [pDau, pWau, pMau] = await Promise.all([
            admin
              .from('user_activity_presence')
              .select('user_id', { count: 'exact', head: true })
              .gte('last_active_at', todayStartIso),
            admin
              .from('user_activity_presence')
              .select('user_id', { count: 'exact', head: true })
              .gte('last_active_at', sevenDaysAgoIso),
            admin
              .from('user_activity_presence')
              .select('user_id', { count: 'exact', head: true })
              .gte('last_active_at', thirtyDaysAgoIso),
          ]);
          dau = pDau.count ?? 0;
          wau = pWau.count ?? 0;
          mau = pMau.count ?? 0;
        }

        // Login history via Supabase client
        const lRes = await admin
          .from('login_history')
          .select('id', { count: 'exact', head: true })
          .eq('event_type', 'login');
        if (!lRes.error) {
          loginHistoryAvailable = true;
          totalLogins = lRes.count ?? 0;
          const [loRes, exRes] = await Promise.all([
            admin
              .from('login_history')
              .select('id', { count: 'exact', head: true })
              .eq('event_type', 'logout'),
            admin
              .from('login_history')
              .select('id', { count: 'exact', head: true })
              .eq('event_type', 'session_expired'),
          ]);
          totalLogouts = loRes.count ?? 0;
          totalSessionExpiries = exRes.count ?? 0;
        } else if (isMissingRelationOrColumnError(lRes.error)) {
          const basicRes = await admin
            .from('login_history')
            .select('id', { count: 'exact', head: true });
          if (!basicRes.error) {
            loginHistoryAvailable = true;
            totalLogins = basicRes.count ?? 0;
          }
        }
      }

      return response.json({
        totalUsers,
        totalEvents,
        totalFeedback,
        registrations: {
          today: registrationsToday,
          thisWeek: registrationsThisWeek,
          thisMonth: registrationsThisMonth,
        },
        activity: {
          activeLast15Min,
          dau,
          wau,
          mau,
          totalLogins,
          totalLogouts,
          totalSessionExpiries,
          presenceAvailable,
          loginHistoryAvailable,
        },
        generatedAt: now.toISOString(),
      });
    } catch (error) {
      console.error('Error fetching admin metrics:', error);
      return requestError(response, 500, 'Unable to fetch admin metrics.');
    }
  }

  // 2. GET /api/admin/users
  async function getUsers(request, response) {
    const adminSession = await requireAdmin(request, response);
    if (!adminSession) return;

    const query = String(request.query?.q ?? '').trim().toLowerCase();
    const page = Math.max(1, parseInt(request.query?.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(request.query?.limit, 10) || 25));
    const offset = (page - 1) * limit;

    try {
      let rows = [];
      let total = 0;

      if (pgPool?.query) {
        const whereClauses = ['deleted_at IS NULL'];
        const params = [];

        if (query) {
          params.push(`%${query}%`);
          whereClauses.push(
            `(LOWER(COALESCE(username, '')) LIKE $1 OR LOWER(COALESCE(full_name, '')) LIKE $1 OR id::text LIKE $1)`,
          );
        }

        const whereSql = `WHERE ${whereClauses.join(' AND ')}`;
        const countRes = await pgPool.query(
          `SELECT COUNT(DISTINCT id)::int AS count FROM public.profiles ${whereSql}`,
          params,
        );
        total = countRes.rows[0]?.count ?? 0;

        const dataParams = [...params, limit, offset];
        const dataSql = `
          SELECT id, username, full_name, date_of_birth, tz, created_at, updated_at
          FROM public.profiles
          ${whereSql}
          ORDER BY created_at DESC, id ASC
          LIMIT $${params.length + 1} OFFSET $${params.length + 2}
        `;
        const dataRes = await pgPool.query(dataSql, dataParams);
        rows = dataRes.rows;

        // Best-effort enrichment with presence
        if (rows.length > 0) {
          const ids = rows.map((r) => r.id);
          try {
            const presRes = await pgPool.query(
              'SELECT user_id, last_active_at, last_login_at FROM public.user_activity_presence WHERE user_id = ANY($1::uuid[])',
              [ids],
            );
            const presMap = new Map(presRes.rows.map((p) => [p.user_id, p]));
            rows = rows.map((r) => ({
              ...r,
              last_active_at: presMap.get(r.id)?.last_active_at ?? null,
              last_login_at: presMap.get(r.id)?.last_login_at ?? null,
            }));
          } catch (err) {
            if (!isMissingRelationOrColumnError(err)) throw err;
          }
        }
      } else {
        let req = admin
          .from('profiles')
          .select('id, username, full_name, date_of_birth, tz, created_at, updated_at', {
            count: 'exact',
          })
          .is('deleted_at', null)
          .order('created_at', { ascending: false })
          .order('id', { ascending: true })
          .range(offset, offset + limit - 1);

        if (query) {
          if (UUID_REGEX.test(query)) {
            req = req.eq('id', query);
          } else {
            req = req.or(`username.ilike.%${query}%,full_name.ilike.%${query}%`);
          }
        }

        const { data, count, error } = await req;
        if (error) throw error;
        rows = data ?? [];
        total = count ?? rows.length;
      }

      // Best-effort enrichment: email (auth.users) and custom themes.
      if (rows.length > 0) {
        const ids = rows.map((r) => r.id);
        const emailMap = new Map();
        const metaMap = new Map();
        // Primary: Supabase Auth admin API (service role). Fallback: auth.users via SQL.
        try {
          await Promise.all(
            ids.map(async (id) => {
              const { data, error } = await admin.auth.admin.getUserById(id);
              if (error) throw error;
              if (data?.user?.email) emailMap.set(id, data.user.email);
              metaMap.set(id, data?.user?.user_metadata ?? {});
            }),
          );
        } catch (err) {
          console.error('Admin auth lookup failed, trying SQL:', err?.message ?? err);
          try {
            if (pgPool?.query) {
              const er = await pgPool.query(
                'SELECT id, email, raw_user_meta_data FROM auth.users WHERE id = ANY($1::uuid[])',
                [ids],
              );
              for (const e of er.rows) {
                if (e.email) emailMap.set(e.id, e.email);
                metaMap.set(e.id, e.raw_user_meta_data ?? {});
              }
            }
          } catch (err2) {
            console.error('Admin users email enrichment failed:', err2?.message ?? err2);
          }
        }

        const themeMap = new Map();
        try {
          let themeRows = [];
          if (pgPool?.query) {
            const tr = await pgPool.query(
              `SELECT user_id, name, primary_color, accent_color, background_color
               FROM public.custom_themes WHERE user_id = ANY($1::uuid[]) ORDER BY created_at`,
              [ids],
            );
            themeRows = tr.rows;
          } else {
            const { data } = await admin
              .from('custom_themes')
              .select('user_id, name, primary_color, accent_color, background_color')
              .in('user_id', ids);
            themeRows = data ?? [];
          }
          for (const t of themeRows) {
            if (!themeMap.has(t.user_id)) themeMap.set(t.user_id, []);
            themeMap.get(t.user_id).push({
              name: t.name,
              primary_color: t.primary_color,
              accent_color: t.accent_color,
              background_color: t.background_color,
            });
          }
        } catch (err) {
          if (!isMissingRelationOrColumnError(err)) {
            console.error('Admin users theme enrichment failed:', err?.message ?? err);
          }
        }

        rows = rows.map((r) => {
          const meta = metaMap.get(r.id) ?? {};
          const email = emailMap.get(r.id) ?? null;
          return {
            ...r,
            email,
            username:
              r.username || meta.username || meta.user_name || (email ? email.split('@')[0] : null),
            full_name: r.full_name || meta.full_name || meta.name || null,
            date_of_birth: r.date_of_birth || meta.date_of_birth || null,
            custom_themes: themeMap.get(r.id) ?? [],
          };
        });
      }

      // Defensive deduplication by UUID
      const seen = new Set();
      const uniqueUsers = [];
      for (const user of rows) {
        if (user?.id && !seen.has(user.id)) {
          seen.add(user.id);
          uniqueUsers.push(user);
        }
      }

      return response.json({
        users: uniqueUsers,
        page,
        limit,
        total,
        hasMore: offset + uniqueUsers.length < total,
      });
    } catch (error) {
      console.error('Error querying admin users:', error);
      return requestError(response, 500, 'Unable to query user directory.');
    }
  }

  // 3. GET /api/admin/users/:userId/activity
  async function getUserActivity(request, response) {
    const adminSession = await requireAdmin(request, response);
    if (!adminSession) return;

    const userId = String(request.params?.userId ?? '').trim();
    if (!UUID_REGEX.test(userId)) {
      return requestError(response, 400, 'Invalid user UUID.');
    }

    const limit = Math.min(200, Math.max(1, parseInt(request.query?.limit, 10) || 100));

    try {
      if (pgPool?.query) {
        try {
          const res = await pgPool.query(
            `SELECT id, user_id, event_type, logged_in_at AS occurred_at, app_version
             FROM public.login_history
             WHERE user_id = $1
             ORDER BY logged_in_at DESC, id DESC
             LIMIT $2`,
            [userId, limit],
          );
          return response.json({
            userId,
            events: res.rows,
            tableAvailable: true,
          });
        } catch (err) {
          if (isMissingRelationOrColumnError(err)) {
            // Try baseline 016 login_history without event_type
            try {
              const fallbackRes = await pgPool.query(
                `SELECT id, user_id, 'login'::text AS event_type, logged_in_at AS occurred_at, app_version
                 FROM public.login_history
                 WHERE user_id = $1
                 ORDER BY logged_in_at DESC, id DESC
                 LIMIT $2`,
                [userId, limit],
              );
              return response.json({
                userId,
                events: fallbackRes.rows,
                tableAvailable: true,
              });
            } catch (innerErr) {
              if (isMissingRelationOrColumnError(innerErr)) {
                return response.json({
                  userId,
                  events: [],
                  tableAvailable: false,
                });
              }
              throw innerErr;
            }
          }
          throw err;
        }
      } else {
        const res = await admin
          .from('login_history')
          .select('id, user_id, event_type, logged_in_at, app_version')
          .eq('user_id', userId)
          .order('logged_in_at', { ascending: false })
          .limit(limit);

        if (!res.error) {
          return response.json({
            userId,
            events: (res.data ?? []).map((row) => ({
              id: row.id,
              user_id: row.user_id,
              event_type: row.event_type ?? 'login',
              occurred_at: row.logged_in_at,
              app_version: row.app_version ?? null,
            })),
            tableAvailable: true,
          });
        }

        if (isMissingRelationOrColumnError(res.error)) {
          const basic = await admin
            .from('login_history')
            .select('id, user_id, logged_in_at, app_version')
            .eq('user_id', userId)
            .order('logged_in_at', { ascending: false })
            .limit(limit);

          if (!basic.error) {
            return response.json({
              userId,
              events: (basic.data ?? []).map((row) => ({
                id: row.id,
                user_id: row.user_id,
                event_type: 'login',
                occurred_at: row.logged_in_at,
                app_version: row.app_version ?? null,
              })),
              tableAvailable: true,
            });
          }

          if (isMissingRelationOrColumnError(basic.error)) {
            return response.json({
              userId,
              events: [],
              tableAvailable: false,
            });
          }
          throw basic.error;
        }

        throw res.error;
      }
    } catch (error) {
      console.error('Error fetching user activity:', error);
      return requestError(response, 500, 'Unable to fetch user activity history.');
    }
  }

  // 4. POST /api/activity/auth-event (authenticated user records own login/logout/session_expired)
  async function recordAuthEvent(request, response) {
    const session = await requireAuth(request, response);
    if (!session) return;

    const userId = session.userId;
    const eventType = String(request.body?.event_type ?? '').trim();
    const appVersion =
      typeof request.body?.app_version === 'string'
        ? request.body.app_version.trim().slice(0, 64)
        : null;

    if (!VALID_AUTH_EVENT_TYPES.includes(eventType)) {
      return requestError(
        response,
        400,
        'Invalid event_type. Expected login, logout, or session_expired.',
      );
    }

    const nowIso = new Date().toISOString();

    try {
      let recorded = false;
      if (pgPool?.query) {
        try {
          await pgPool.query(
            `INSERT INTO public.login_history (user_id, event_type, logged_in_at, app_version)
             VALUES ($1, $2, $3, $4)`,
            [userId, eventType, nowIso, appVersion],
          );
          recorded = true;
        } catch (err) {
          if (isMissingRelationOrColumnError(err)) {
            if (eventType === 'login') {
              try {
                await pgPool.query(
                  `INSERT INTO public.login_history (user_id, logged_in_at, app_version)
                   VALUES ($1, $2, $3)`,
                  [userId, nowIso, appVersion],
                );
                recorded = true;
              } catch (innerErr) {
                if (!isMissingRelationOrColumnError(innerErr)) throw innerErr;
              }
            }
          } else {
            throw err;
          }
        }

        // Update presence table if available
        try {
          if (eventType === 'login') {
            await pgPool.query(
              `INSERT INTO public.user_activity_presence (user_id, last_active_at, last_login_at, app_version)
               VALUES ($1, $2, $2, $3)
               ON CONFLICT (user_id) DO UPDATE
               SET last_active_at = EXCLUDED.last_active_at,
                   last_login_at = EXCLUDED.last_login_at,
                   app_version = COALESCE(EXCLUDED.app_version, public.user_activity_presence.app_version)`,
              [userId, nowIso, appVersion],
            );
          } else {
            await pgPool.query(
              `INSERT INTO public.user_activity_presence (user_id, last_active_at, app_version)
               VALUES ($1, $2, $3)
               ON CONFLICT (user_id) DO UPDATE
               SET last_active_at = EXCLUDED.last_active_at,
                   app_version = COALESCE(EXCLUDED.app_version, public.user_activity_presence.app_version)`,
              [userId, nowIso, appVersion],
            );
          }
        } catch (err) {
          if (!isMissingRelationOrColumnError(err)) throw err;
        }
      } else {
        const ins = await admin.from('login_history').insert({
          user_id: userId,
          event_type: eventType,
          logged_in_at: nowIso,
          app_version: appVersion,
        });
        if (!ins.error) {
          recorded = true;
        } else if (isMissingRelationOrColumnError(ins.error) && eventType === 'login') {
          const fallbackIns = await admin.from('login_history').insert({
            user_id: userId,
            logged_in_at: nowIso,
            app_version: appVersion,
          });
          if (!fallbackIns.error) recorded = true;
        } else if (!isMissingRelationOrColumnError(ins.error)) {
          throw ins.error;
        }

        const presPayload = {
          user_id: userId,
          last_active_at: nowIso,
          ...(eventType === 'login' ? { last_login_at: nowIso } : {}),
          ...(appVersion ? { app_version: appVersion } : {}),
        };
        const presUpsert = await admin
          .from('user_activity_presence')
          .upsert(presPayload, { onConflict: 'user_id' });
        if (presUpsert.error && !isMissingRelationOrColumnError(presUpsert.error)) {
          throw presUpsert.error;
        }
      }

      return response.status(recorded ? 201 : 202).json({
        recorded,
        user_id: userId,
        event_type: eventType,
        occurred_at: nowIso,
        ...(recorded ? {} : { reason: 'migration_pending' }),
      });
    } catch (error) {
      console.error('Error recording auth event:', error);
      return requestError(response, 500, 'Unable to record activity event.');
    }
  }

  // 5. POST /api/activity/heartbeat
  async function recordHeartbeat(request, response) {
    const session = await requireAuth(request, response);
    if (!session) return;

    const userId = session.userId;
    const appVersion =
      typeof request.body?.app_version === 'string'
        ? request.body.app_version.trim().slice(0, 64)
        : null;
    const nowIso = new Date().toISOString();

    try {
      let recorded = false;
      if (pgPool?.query) {
        try {
          await pgPool.query(
            `INSERT INTO public.user_activity_presence (user_id, last_active_at, app_version)
             VALUES ($1, $2, $3)
             ON CONFLICT (user_id) DO UPDATE
             SET last_active_at = EXCLUDED.last_active_at,
                 app_version = COALESCE(EXCLUDED.app_version, public.user_activity_presence.app_version)`,
            [userId, nowIso, appVersion],
          );
          recorded = true;
        } catch (err) {
          if (!isMissingRelationOrColumnError(err)) throw err;
        }
      } else {
        const res = await admin
          .from('user_activity_presence')
          .upsert(
            {
              user_id: userId,
              last_active_at: nowIso,
              ...(appVersion ? { app_version: appVersion } : {}),
            },
            { onConflict: 'user_id' },
          );
        if (!res.error) {
          recorded = true;
        } else if (!isMissingRelationOrColumnError(res.error)) {
          throw res.error;
        }
      }

      return response.status(recorded ? 200 : 202).json({
        recorded,
        last_active_at: nowIso,
      });
    } catch (error) {
      console.error('Error recording heartbeat:', error);
      return requestError(response, 500, 'Unable to record heartbeat.');
    }
  }

  // 6. GET /api/admin/feedback
  async function getFeedback(request, response) {
    const adminSession = await requireAdmin(request, response);
    if (!adminSession) return;

    const statusFilter = String(request.query?.status ?? 'all').trim().toLowerCase();
    if (statusFilter !== 'all' && !VALID_FEEDBACK_STATUSES.includes(statusFilter)) {
      return requestError(response, 400, 'Invalid feedback status filter.');
    }

    const limit = Math.min(200, Math.max(1, parseInt(request.query?.limit, 10) || 100));

    try {
      let rows = [];
      let triageColumnsAvailable = true;

      if (pgPool?.query) {
        try {
          const params = [];
          let sql = `
            SELECT f.id, f.user_id, f.message, f.rating, f.category, f.status, f.admin_note,
                   f.created_at, f.updated_at, p.username, p.full_name
            FROM public.user_feedback f
            LEFT JOIN public.profiles p ON p.id = f.user_id
          `;
          if (statusFilter !== 'all') {
            params.push(statusFilter);
            sql += ' WHERE f.status = $1';
          }
          params.push(limit);
          sql += ` ORDER BY f.created_at DESC LIMIT $${params.length}`;

          const res = await pgPool.query(sql, params);
          rows = res.rows;
        } catch (err) {
          if (isMissingRelationOrColumnError(err)) {
            triageColumnsAvailable = false;
            const res = await pgPool.query(
              `SELECT f.id, f.user_id, f.message, f.rating, f.created_at, p.username, p.full_name
               FROM public.user_feedback f
               LEFT JOIN public.profiles p ON p.id = f.user_id
               ORDER BY f.created_at DESC
               LIMIT $1`,
              [limit],
            );
            rows = res.rows;
          } else {
            throw err;
          }
        }
      } else {
        let req = admin
          .from('user_feedback')
          .select('id, user_id, message, rating, category, status, admin_note, created_at, updated_at')
          .order('created_at', { ascending: false })
          .limit(limit);

        if (statusFilter !== 'all') {
          req = req.eq('status', statusFilter);
        }

        const res = await req;
        if (!res.error) {
          rows = res.data ?? [];
        } else if (isMissingRelationOrColumnError(res.error)) {
          triageColumnsAvailable = false;
          const fallback = await admin
            .from('user_feedback')
            .select('id, user_id, message, rating, created_at')
            .order('created_at', { ascending: false })
            .limit(limit);
          if (fallback.error) throw fallback.error;
          rows = fallback.data ?? [];
        } else {
          throw res.error;
        }
      }

      return response.json({
        feedback: rows,
        triageColumnsAvailable,
      });
    } catch (error) {
      console.error('Error querying admin feedback:', error);
      return requestError(response, 500, 'Unable to load feedback inbox.');
    }
  }

  // 7. PATCH /api/admin/feedback/:id
  async function patchFeedback(request, response) {
    const adminSession = await requireAdmin(request, response);
    if (!adminSession) return;

    const feedbackId = String(request.params?.id ?? '').trim();
    if (!UUID_REGEX.test(feedbackId)) {
      return requestError(response, 400, 'Invalid feedback ID.');
    }

    const body = request.body;
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return requestError(response, 400, 'Invalid request payload.');
    }

    // Reject attempts to mutate immutable user-submitted fields
    for (const field of IMMUTABLE_FEEDBACK_FIELDS) {
      if (Object.prototype.hasOwnProperty.call(body, field)) {
        return requestError(response, 400, `Field '${field}' is immutable and cannot be modified.`);
      }
    }

    const { status, admin_note } = body;

    if (status === undefined && admin_note === undefined) {
      return requestError(response, 400, 'At least one of status or admin_note must be provided.');
    }

    if (status !== undefined && (typeof status !== 'string' || !VALID_FEEDBACK_STATUSES.includes(status))) {
      return requestError(response, 400, 'Invalid feedback status.');
    }

    if (admin_note !== undefined && admin_note !== null && typeof admin_note !== 'string') {
      return requestError(response, 400, 'admin_note must be a string or null.');
    }

    try {
      const normalizedNote =
        admin_note === undefined
          ? undefined
          : admin_note === null || admin_note.trim() === ''
            ? null
            : admin_note.trim();

      if (pgPool?.query) {
        const res = await pgPool.query(
          `UPDATE public.user_feedback
           SET status = COALESCE($1, status),
               admin_note = CASE WHEN $2::boolean THEN $3 ELSE admin_note END,
               updated_at = NOW()
           WHERE id = $4
           RETURNING *`,
          [status ?? null, admin_note !== undefined, normalizedNote ?? null, feedbackId],
        );

        if (res.rowCount === 0) {
          return requestError(response, 404, 'Feedback item not found.');
        }
        return response.json({ feedback: res.rows[0] });
      } else {
        const updatePayload = { updated_at: new Date().toISOString() };
        if (status !== undefined) updatePayload.status = status;
        if (admin_note !== undefined) updatePayload.admin_note = normalizedNote;

        const { data, error } = await admin
          .from('user_feedback')
          .update(updatePayload)
          .eq('id', feedbackId)
          .select()
          .maybeSingle();

        if (error) {
          if (isMissingRelationOrColumnError(error)) {
            return requestError(
              response,
              409,
              'Feedback triage columns are not yet enabled in the database (Migration 016 pending).',
            );
          }
          throw error;
        }
        if (!data) {
          return requestError(response, 404, 'Feedback item not found.');
        }
        return response.json({ feedback: data });
      }
    } catch (error) {
      if (isMissingRelationOrColumnError(error)) {
        return requestError(
          response,
          409,
          'Feedback triage columns are not yet enabled in the database (Migration 016 pending).',
        );
      }
      console.error('Error updating feedback:', error);
      return requestError(response, 500, 'Unable to update feedback record.');
    }
  }

  return {
    requireAdmin,
    getMetrics,
    getUsers,
    getUserActivity,
    recordAuthEvent,
    recordHeartbeat,
    getFeedback,
    patchFeedback,
  };
}
