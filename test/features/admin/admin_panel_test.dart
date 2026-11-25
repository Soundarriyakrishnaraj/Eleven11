import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eleven11/core/security/user_activity_tracker.dart';
import 'package:eleven11/features/admin/screens/admin_dashboard_screen.dart';
import 'package:eleven11/features/admin/screens/admin_users_screen.dart';
import 'package:eleven11/features/admin/services/admin_service.dart';

class _FakeAdminService extends AdminService {
  _FakeAdminService({
    required this.authorized,
    required this.metrics,
    required this.usersPages,
    required this.activityByUser,
  }) : super(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          backendUrl: 'https://test.invalid',
        );

  final bool authorized;
  final AdminMetrics metrics;
  final Map<int, AdminUsersPage> usersPages;
  final Map<String, AdminUserActivityResult> activityByUser;

  @override
  Future<bool> isCurrentUserAuthorizedAdmin() async => authorized;

  @override
  Future<AdminMetrics> fetchMetrics() async => metrics;

  @override
  Future<AdminUsersPage> fetchUsers({
    String query = '',
    int page = 1,
    int limit = 25,
  }) async {
    final pageData = usersPages[page] ??
        const AdminUsersPage(
          users: [],
          page: 1,
          limit: 25,
          total: 0,
          hasMore: false,
          source: 'backend',
        );
    if (query.trim().isEmpty) return pageData;
    final q = query.trim().toLowerCase();
    final filtered = pageData.users.where((u) {
      return (u['username'] ?? '').toString().toLowerCase().contains(q) ||
          (u['full_name'] ?? '').toString().toLowerCase().contains(q) ||
          (u['id'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
    return AdminUsersPage(
      users: filtered,
      page: 1,
      limit: limit,
      total: filtered.length,
      hasMore: false,
      source: 'backend',
    );
  }

  @override
  Future<AdminUserActivityResult> fetchUserActivity(String userId) async {
    return activityByUser[userId] ??
        const AdminUserActivityResult(
          events: [],
          tableAvailable: true,
          source: 'backend',
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserActivityTracker', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      UserActivityTracker.instance.clearExplicitSignOutFlag();
    });

    test('records login, logout, and session_expired accurately without fabricating logout', () async {
      final recordedRequests = <Map<String, dynamic>>[];
      final mockHttp = MockClient((req) async {
        recordedRequests.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'recorded': true}), 201);
      });

      const userId = '11111111-2222-3333-4444-555555555555';

      await UserActivityTracker.instance.recordEvent(
        userId: userId,
        eventType: 'login',
        accessToken: 'jwt-a',
        httpClient: mockHttp,
      );
      await UserActivityTracker.instance.recordEvent(
        userId: userId,
        eventType: 'logout',
        accessToken: 'jwt-a',
        httpClient: mockHttp,
      );
      await UserActivityTracker.instance.recordEvent(
        userId: userId,
        eventType: 'session_expired',
        accessToken: 'jwt-a',
        httpClient: mockHttp,
      );

      expect(recordedRequests.map((r) => r['event_type']), [
        'login',
        'logout',
        'session_expired',
      ]);

      final localEvents = await UserActivityTracker.instance.getEventsForUser(userId);
      expect(localEvents.length, 3);
      // Most recent first
      expect(localEvents[0]['event_type'], 'session_expired');
      expect(localEvents[1]['event_type'], 'logout');
      expect(localEvents[2]['event_type'], 'login');
    });

    test('rejects invalid event types', () async {
      expect(
        () => UserActivityTracker.instance.recordEvent(
          userId: '11111111-2222-3333-4444-555555555555',
          eventType: 'invalid_event',
        ),
        throwsArgumentError,
      );
    });
  });

  group('AdminDashboardScreen', () {
    testWidgets('shows real metrics and displays dash (never fabricated values) when Migration 016 is pending', (tester) async {
      final fakeService = _FakeAdminService(
        authorized: true,
        metrics: AdminMetrics(
          totalUsers: 4,
          totalEvents: 12,
          totalFeedback: 3,
          registrationsToday: 1,
          registrationsThisWeek: 2,
          registrationsThisMonth: 4,
          activeLast15Min: null,
          dau: null,
          wau: null,
          mau: null,
          totalLogins: null,
          totalLogouts: null,
          totalSessionExpiries: null,
          presenceAvailable: false,
          loginHistoryAvailable: false,
          source: 'backend',
          generatedAt: DateTime.utc(2026, 11, 25, 11, 0),
        ),
        usersPages: const {},
        activityByUser: const {},
      );

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(adminService: fakeService)),
      );
      await tester.pumpAndSettle();

      expect(find.text('4'), findsOneWidget); // Total Users
      expect(find.text('12'), findsOneWidget); // Total Events
      expect(find.text('3'), findsOneWidget); // Feedback
      expect(find.text('—'), findsNWidgets(5)); // Active(15m), DAU, WAU, MAU, Total Logins
    });

    testWidgets('rejects unauthorized ordinary users with ACCESS DENIED', (tester) async {
      final fakeService = _FakeAdminService(
        authorized: false,
        metrics: AdminMetrics(
          totalUsers: 0,
          totalEvents: 0,
          totalFeedback: 0,
          registrationsToday: 0,
          registrationsThisWeek: 0,
          registrationsThisMonth: 0,
          activeLast15Min: null,
          dau: null,
          wau: null,
          mau: null,
          totalLogins: null,
          totalLogouts: null,
          totalSessionExpiries: null,
          presenceAvailable: false,
          loginHistoryAvailable: false,
          source: 'backend',
          generatedAt: DateTime.utc(2026, 11, 25, 11, 0),
        ),
        usersPages: const {},
        activityByUser: const {},
      );

      await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(adminService: fakeService)),
      );
      await tester.pumpAndSettle();

      expect(find.text('ACCESS DENIED'), findsOneWidget);
      expect(find.text('Administrator Privileges Required'), findsOneWidget);
    });
  });

  group('AdminUsersScreen', () {
    testWidgets('lists multiple unique users with pagination and displays chronological login/logout/expired history', (tester) async {
      const userA = '11111111-2222-3333-4444-555555555555';
      const userB = '66666666-7777-8888-9999-aaaaaaaaaaaa';

      final fakeService = _FakeAdminService(
        authorized: true,
        metrics: AdminMetrics(
          totalUsers: 2,
          totalEvents: 0,
          totalFeedback: 0,
          registrationsToday: 0,
          registrationsThisWeek: 0,
          registrationsThisMonth: 2,
          activeLast15Min: 1,
          dau: 1,
          wau: 2,
          mau: 2,
          totalLogins: 2,
          totalLogouts: 1,
          totalSessionExpiries: 1,
          presenceAvailable: true,
          loginHistoryAvailable: true,
          source: 'backend',
          generatedAt: DateTime.utc(2026, 11, 25, 11, 0),
        ),
        usersPages: {
          1: const AdminUsersPage(
            users: [
              {
                'id': userA,
                'username': 'alice_dev',
                'full_name': 'Alice Developer',
                'tz': 'UTC',
                'created_at': '2026-11-20T10:00:00Z',
              },
              {
                'id': userB,
                'username': 'bob_tester',
                'full_name': 'Bob Tester',
                'tz': 'Asia/Kolkata',
                'created_at': '2026-11-25T05:00:00Z',
              },
            ],
            page: 1,
            limit: 25,
            total: 2,
            hasMore: false,
            source: 'backend',
          ),
        },
        activityByUser: {
          userA: const AdminUserActivityResult(
            events: [
              {
                'id': 2,
                'user_id': userA,
                'event_type': 'logout',
                'occurred_at': '2026-11-25T10:00:00Z',
              },
              {
                'id': 1,
                'user_id': userA,
                'event_type': 'login',
                'occurred_at': '2026-11-25T09:00:00Z',
              },
            ],
            tableAvailable: true,
            source: 'backend',
          ),
        },
      );

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: AdminUsersScreen(adminService: fakeService)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Showing 2 of 2 unique users'), findsOneWidget);
      expect(find.text('alice_dev'), findsOneWidget);
      expect(find.text('bob_tester'), findsOneWidget);

      // Tap first user row to inspect chronological login/logout timeline
      await tester.tap(find.text('alice_dev'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN, LOGOUT & SESSION HISTORY'), findsOneWidget);
      expect(find.text('User Logged Out'), findsOneWidget);
      expect(find.text('User Logged In'), findsOneWidget);
    });
  });
}
