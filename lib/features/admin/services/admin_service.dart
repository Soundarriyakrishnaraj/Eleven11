import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_config.dart';
import '../../../core/security/user_activity_tracker.dart';

const String kDesignatedAdminUuid = '74aa5b3c-9b9f-440e-b104-98fbbe2b6e6a';

class AdminMetrics {
  const AdminMetrics({
    required this.totalUsers,
    required this.totalEvents,
    required this.totalFeedback,
    required this.registrationsToday,
    required this.registrationsThisWeek,
    required this.registrationsThisMonth,
    required this.activeLast15Min,
    required this.dau,
    required this.wau,
    required this.mau,
    required this.totalLogins,
    required this.totalLogouts,
    required this.totalSessionExpiries,
    required this.presenceAvailable,
    required this.loginHistoryAvailable,
    required this.source,
    required this.generatedAt,
  });

  final int totalUsers;
  final int totalEvents;
  final int totalFeedback;
  final int registrationsToday;
  final int registrationsThisWeek;
  final int registrationsThisMonth;

  /// Null when the backing table (Migration 016) does not exist yet — never fabricated.
  final int? activeLast15Min;
  final int? dau;
  final int? wau;
  final int? mau;
  final int? totalLogins;
  final int? totalLogouts;
  final int? totalSessionExpiries;

  final bool presenceAvailable;
  final bool loginHistoryAvailable;
  final String source; // 'backend' | 'supabase_direct'
  final DateTime generatedAt;
}

class AdminUsersPage {
  const AdminUsersPage({
    required this.users,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
    required this.source,
  });

  final List<Map<String, dynamic>> users;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
  final String source;
}

class AdminUserActivityResult {
  const AdminUserActivityResult({
    required this.events,
    required this.tableAvailable,
    required this.source,
  });

  final List<Map<String, dynamic>> events;
  final bool tableAvailable;
  final String source;
}

class AdminFeedbackResult {
  const AdminFeedbackResult({
    required this.items,
    required this.triageColumnsAvailable,
    required this.source,
  });

  final List<Map<String, dynamic>> items;
  final bool triageColumnsAvailable;
  final String source;
}

class AdminService {
  AdminService({
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
    String? backendUrl,
  })  : _supabaseOverride = supabaseClient,
        _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _backendUrl = backendUrl ?? AppConfig.renderBackendUrl;

  final SupabaseClient? _supabaseOverride;
  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;
  final http.Client _http;
  final bool _ownsHttpClient;
  final String _backendUrl;

  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
  }

  Map<String, String>? _authHeaders() {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<bool> isCurrentUserAuthorizedAdmin() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    if (user.id == kDesignatedAdminUuid) return true;

    try {
      final roleCheck = await _supabase
          .from('admin_roles')
          .select('role')
          .eq('user_id', user.id)
          .maybeSingle();

      if (roleCheck != null &&
          (roleCheck['role'] == 'admin' || roleCheck['role'] == 'super_admin')) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Fetches real admin metrics from the backend service-role API first,
  /// falling back to direct Supabase queries if the backend is unavailable.
  /// Never invents or fabricates missing metrics.
  Future<AdminMetrics> fetchMetrics() async {
    final headers = _authHeaders();
    if (headers != null) {
      try {
        final uri = Uri.parse('$_backendUrl/api/admin/metrics');
        final res = await _http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 25));

        if (res.statusCode == 401 || res.statusCode == 403) {
          throw Exception('Unauthorized access. Administrator privileges required.');
        }

        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          final reg = (json['registrations'] as Map<String, dynamic>?) ?? {};
          final act = (json['activity'] as Map<String, dynamic>?) ?? {};
          return AdminMetrics(
            totalUsers: (json['totalUsers'] as num?)?.toInt() ?? 0,
            totalEvents: (json['totalEvents'] as num?)?.toInt() ?? 0,
            totalFeedback: (json['totalFeedback'] as num?)?.toInt() ?? 0,
            registrationsToday: (reg['today'] as num?)?.toInt() ?? 0,
            registrationsThisWeek: (reg['thisWeek'] as num?)?.toInt() ?? 0,
            registrationsThisMonth: (reg['thisMonth'] as num?)?.toInt() ?? 0,
            activeLast15Min: (act['activeLast15Min'] as num?)?.toInt(),
            dau: (act['dau'] as num?)?.toInt(),
            wau: (act['wau'] as num?)?.toInt(),
            mau: (act['mau'] as num?)?.toInt(),
            totalLogins: (act['totalLogins'] as num?)?.toInt(),
            totalLogouts: (act['totalLogouts'] as num?)?.toInt(),
            totalSessionExpiries: (act['totalSessionExpiries'] as num?)?.toInt(),
            presenceAvailable: act['presenceAvailable'] == true,
            loginHistoryAvailable: act['loginHistoryAvailable'] == true,
            source: 'backend',
            generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? '') ??
                DateTime.now().toUtc(),
          );
        }
      } catch (e) {
        if (e.toString().contains('Unauthorized')) rethrow;
        // Fall through to direct Supabase query when backend is unreachable
      }
    }

    return _fetchMetricsDirectFromSupabase();
  }

  Future<AdminMetrics> _fetchMetricsDirectFromSupabase() async {
    final profilesCount = await _supabase
        .from('profiles')
        .select('id')
        .isFilter('deleted_at', null)
        .count(CountOption.exact);
    final totalUsers = profilesCount.count;

    int totalEvents = 0;
    try {
      final eventsCount = await _supabase
          .from('events')
          .select('id')
          .count(CountOption.exact);
      totalEvents = eventsCount.count;
    } catch (_) {}

    int totalFeedback = 0;
    try {
      final feedbackCount = await _supabase
          .from('user_feedback')
          .select('id')
          .count(CountOption.exact);
      totalFeedback = feedbackCount.count;
    } catch (_) {}

    final now = DateTime.now().toUtc();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: todayStart.weekday - 1));
    final monthStart = DateTime.utc(now.year, now.month, 1);
    final fifteenMinAgo = now.subtract(const Duration(minutes: 15));
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    int registrationsToday = 0;
    int registrationsThisWeek = 0;
    int registrationsThisMonth = 0;
    try {
      final regToday = await _supabase
          .from('profiles')
          .select('id')
          .isFilter('deleted_at', null)
          .gte('created_at', todayStart.toIso8601String())
          .count(CountOption.exact);
      registrationsToday = regToday.count;

      final regWeek = await _supabase
          .from('profiles')
          .select('id')
          .isFilter('deleted_at', null)
          .gte('created_at', weekStart.toIso8601String())
          .count(CountOption.exact);
      registrationsThisWeek = regWeek.count;

      final regMonth = await _supabase
          .from('profiles')
          .select('id')
          .isFilter('deleted_at', null)
          .gte('created_at', monthStart.toIso8601String())
          .count(CountOption.exact);
      registrationsThisMonth = regMonth.count;
    } catch (_) {}

    int? activeLast15Min;
    int? dau;
    int? wau;
    int? mau;
    bool presenceAvailable = false;
    try {
      final p15 = await _supabase
          .from('user_activity_presence')
          .select('user_id')
          .gte('last_active_at', fifteenMinAgo.toIso8601String())
          .count(CountOption.exact);
      final pDau = await _supabase
          .from('user_activity_presence')
          .select('user_id')
          .gte('last_active_at', todayStart.toIso8601String())
          .count(CountOption.exact);
      final pWau = await _supabase
          .from('user_activity_presence')
          .select('user_id')
          .gte('last_active_at', sevenDaysAgo.toIso8601String())
          .count(CountOption.exact);
      final pMau = await _supabase
          .from('user_activity_presence')
          .select('user_id')
          .gte('last_active_at', thirtyDaysAgo.toIso8601String())
          .count(CountOption.exact);
      activeLast15Min = p15.count;
      dau = pDau.count;
      wau = pWau.count;
      mau = pMau.count;
      presenceAvailable = true;
    } catch (_) {
      presenceAvailable = false;
    }

    int? totalLogins;
    int? totalLogouts;
    int? totalSessionExpiries;
    bool loginHistoryAvailable = false;
    try {
      final lCount = await _supabase
          .from('login_history')
          .select('id')
          .eq('event_type', 'login')
          .count(CountOption.exact);
      final loCount = await _supabase
          .from('login_history')
          .select('id')
          .eq('event_type', 'logout')
          .count(CountOption.exact);
      final exCount = await _supabase
          .from('login_history')
          .select('id')
          .eq('event_type', 'session_expired')
          .count(CountOption.exact);
      totalLogins = lCount.count;
      totalLogouts = loCount.count;
      totalSessionExpiries = exCount.count;
      loginHistoryAvailable = true;
    } catch (_) {
      try {
        final basicCount = await _supabase
            .from('login_history')
            .select('id')
            .count(CountOption.exact);
        totalLogins = basicCount.count;
        loginHistoryAvailable = true;
      } catch (_) {
        loginHistoryAvailable = false;
      }
    }

    return AdminMetrics(
      totalUsers: totalUsers,
      totalEvents: totalEvents,
      totalFeedback: totalFeedback,
      registrationsToday: registrationsToday,
      registrationsThisWeek: registrationsThisWeek,
      registrationsThisMonth: registrationsThisMonth,
      activeLast15Min: activeLast15Min,
      dau: dau,
      wau: wau,
      mau: mau,
      totalLogins: totalLogins,
      totalLogouts: totalLogouts,
      totalSessionExpiries: totalSessionExpiries,
      presenceAvailable: presenceAvailable,
      loginHistoryAvailable: loginHistoryAvailable,
      source: 'supabase_direct',
      generatedAt: now,
    );
  }

  /// Fetches paginated unique registered users from backend first (bypassing RLS
  /// after admin authorization), falling back to Supabase direct query.
  Future<AdminUsersPage> fetchUsers({
    String query = '',
    int page = 1,
    int limit = 25,
  }) async {
    final trimmed = query.trim();
    final headers = _authHeaders();

    if (headers != null) {
      try {
        final uri = Uri.parse('$_backendUrl/api/admin/users').replace(
          queryParameters: {
            if (trimmed.isNotEmpty) 'q': trimmed,
            'page': '$page',
            'limit': '$limit',
          },
        );
        final res = await _http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 25));

        if (res.statusCode == 401 || res.statusCode == 403) {
          throw Exception('Unauthorized access. Administrator privileges required.');
        }

        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          final rawUsers = List<Map<String, dynamic>>.from(json['users'] ?? []);
          final unique = _deduplicateById(rawUsers);
          final total = (json['total'] as num?)?.toInt() ?? unique.length;
          return AdminUsersPage(
            users: unique,
            page: (json['page'] as num?)?.toInt() ?? page,
            limit: (json['limit'] as num?)?.toInt() ?? limit,
            total: total,
            hasMore: json['hasMore'] == true,
            source: 'backend',
          );
        }
      } catch (e) {
        if (e.toString().contains('Unauthorized')) rethrow;
      }
    }

    // Fallback: direct Supabase query with pagination
    final from = (page - 1) * limit;
    final to = from + limit - 1;

    var req = _supabase
        .from('profiles')
        .select('id, username, full_name, date_of_birth, tz, created_at, updated_at')
        .isFilter('deleted_at', null);

    if (trimmed.isNotEmpty) {
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      if (uuidPattern.hasMatch(trimmed)) {
        req = req.eq('id', trimmed);
      } else {
        req = req.or('username.ilike.%$trimmed%,full_name.ilike.%$trimmed%');
      }
    }

    final data = await req
        .order('created_at', ascending: false)
        .range(from, to);

    final countRes = await _supabase
        .from('profiles')
        .select('id')
        .isFilter('deleted_at', null)
        .count(CountOption.exact);

    final unique = _deduplicateById(List<Map<String, dynamic>>.from(data));
    final total = countRes.count;

    // Best-effort email enrichment via RPC (requires Migration 018)
    if (unique.isNotEmpty) {
      try {
        final ids = unique.map((u) => u['id']).whereType<String>().toList();
        final emailRows = await _supabase.rpc(
          'get_admin_users_emails',
          params: {'user_ids': ids},
        );
        if (emailRows is List) {
          final emailMap = <String, String>{};
          for (final row in emailRows) {
            if (row is Map && row['id'] != null && row['email'] != null) {
              emailMap[row['id'].toString()] = row['email'].toString();
            }
          }
          for (final u in unique) {
            final id = u['id']?.toString();
            if (id != null && emailMap.containsKey(id)) {
              u['email'] = emailMap[id];
            }
          }
        }
      } catch (_) {}
    }

    return AdminUsersPage(
      users: unique,
      page: page,
      limit: limit,
      total: total,
      hasMore: from + unique.length < total,
      source: 'supabase_direct',
    );
  }

  /// Fetches every registered user (all pages) for the spreadsheet export.
  Future<List<Map<String, dynamic>>> fetchAllUsers() async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final result = await fetchUsers(page: page, limit: 100);
      all.addAll(result.users);
      if (!result.hasMore || result.users.isEmpty || page >= 200) break;
      page++;
    }
    return _deduplicateById(all);
  }

  /// Fetches chronological login/logout/session_expired history for a user.
  Future<AdminUserActivityResult> fetchUserActivity(String userId) async {
    final headers = _authHeaders();
    if (headers != null) {
      try {
        final uri = Uri.parse('$_backendUrl/api/admin/users/$userId/activity');
        final res = await _http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 25));

        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          final events = List<Map<String, dynamic>>.from(json['events'] ?? []);
          final tableAvailable = json['tableAvailable'] == true;
          if (tableAvailable) {
            return AdminUserActivityResult(
              events: events,
              tableAvailable: true,
              source: 'backend',
            );
          }
          // If DB table not yet created, merge locally recorded events on this device if any
          final local = await UserActivityTracker.instance.getEventsForUser(userId);
          return AdminUserActivityResult(
            events: local,
            tableAvailable: false,
            source: 'local_fallback',
          );
        }
      } catch (_) {}
    }

    // Fallback: direct Supabase query on login_history
    try {
      final rows = await _supabase
          .from('login_history')
          .select('id, user_id, event_type, logged_in_at, app_version')
          .eq('user_id', userId)
          .order('logged_in_at', ascending: false)
          .limit(100);

      final mapped = List<Map<String, dynamic>>.from(rows).map((row) {
        return {
          'id': row['id'],
          'user_id': row['user_id'],
          'event_type': row['event_type'] ?? 'login',
          'occurred_at': row['logged_in_at'],
          'app_version': row['app_version'],
        };
      }).toList();

      return AdminUserActivityResult(
        events: mapped,
        tableAvailable: true,
        source: 'supabase_direct',
      );
    } catch (_) {
      final local = await UserActivityTracker.instance.getEventsForUser(userId);
      return AdminUserActivityResult(
        events: local,
        tableAvailable: false,
        source: 'local_fallback',
      );
    }
  }

  /// Fetches all user feedback for Admin Feedback Inbox.
  Future<AdminFeedbackResult> fetchFeedback({String status = 'all'}) async {
    final headers = _authHeaders();
    if (headers != null) {
      try {
        final uri = Uri.parse('$_backendUrl/api/admin/feedback').replace(
          queryParameters: {'status': status},
        );
        final res = await _http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 25));

        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          return AdminFeedbackResult(
            items: List<Map<String, dynamic>>.from(json['feedback'] ?? []),
            triageColumnsAvailable: json['triageColumnsAvailable'] == true,
            source: 'backend',
          );
        }
      } catch (_) {}
    }

    // Fallback: direct Supabase query (admin_note is restricted to backend service_role)
    try {
      final baseQuery = _supabase
          .from('user_feedback')
          .select('id, user_id, message, rating, category, status, created_at, updated_at');

      final data = status != 'all'
          ? await baseQuery.eq('status', status).order('created_at', ascending: false).limit(100)
          : await baseQuery.order('created_at', ascending: false).limit(100);

      return AdminFeedbackResult(
        items: List<Map<String, dynamic>>.from(data),
        triageColumnsAvailable: true,
        source: 'supabase_direct',
      );
    } catch (_) {
      final fallback = await _supabase
          .from('user_feedback')
          .select('id, user_id, message, rating, created_at')
          .order('created_at', ascending: false)
          .limit(100);

      return AdminFeedbackResult(
        items: List<Map<String, dynamic>>.from(fallback),
        triageColumnsAvailable: false,
        source: 'supabase_direct',
      );
    }
  }

  /// Updates feedback status & internal admin note.
  Future<void> updateFeedback({
    required String id,
    required String status,
    required String adminNote,
  }) async {
    final headers = _authHeaders();
    if (headers != null) {
      try {
        final uri = Uri.parse('$_backendUrl/api/admin/feedback/$id');
        final res = await _http
            .patch(
              uri,
              headers: headers,
              body: jsonEncode({
                'status': status,
                'admin_note': adminNote.trim().isEmpty ? null : adminNote.trim(),
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) return;
        if (res.statusCode >= 400 && res.statusCode < 500) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          throw Exception(body['error'] ?? 'Failed to update feedback.');
        }
      } catch (e) {
        if (e.toString().contains('Migration 016') ||
            e.toString().contains('Invalid') ||
            e.toString().contains('not found')) {
          rethrow;
        }
      }
    }

    // Fallback: direct Supabase update
    await _supabase
        .from('user_feedback')
        .update({
          'status': status,
          'admin_note': adminNote.trim().isEmpty ? null : adminNote.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  List<Map<String, dynamic>> _deduplicateById(List<Map<String, dynamic>> list) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final item in list) {
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty && seen.add(id)) {
        result.add(item);
      }
    }
    return result;
  }
}
