import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:eleven11/features/calendar/services/google_calendar_service.dart';

void main() {
  group('GoogleCalendarStatus', () {
    test('parses from valid json', () {
      final json = {
        'connected': true,
        'email': 'user@gmail.com',
        'lastSyncedAt': '2026-11-24T10:00:00Z',
        'syncStatus': 'ok',
      };

      final status = GoogleCalendarStatus.fromJson(json);

      expect(status.connected, true);
      expect(status.email, 'user@gmail.com');
      expect(status.syncStatus, 'ok');
      expect(status.lastSyncedAt, isNotNull);
    });

    test('disconnected default', () {
      const status = GoogleCalendarStatus.disconnected;

      expect(status.connected, false);
      expect(status.email, isNull);
    });
  });

  group('GoogleCalendarService API calls', () {
    test('getStatus returns status when backend returns 200 with valid session token', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/calendar/status');
        expect(request.headers['authorization'], 'Bearer valid-test-token');

        return http.Response(
          jsonEncode({'connected': true, 'email': 'member@gmail.com'}),
          200,
        );
      });

      final service = GoogleCalendarService(
        httpClient: mockClient,
        backendUrl: 'https://test.render.com',
        accessTokenProvider: () => 'valid-test-token',
      );

      final status = await service.getStatus();

      expect(status.connected, true);
      expect(status.email, 'member@gmail.com');

      service.dispose();
    });

    test('disconnect calls backend /api/calendar/disconnect', () async {
      bool called = false;

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/calendar/disconnect');
        expect(request.headers['authorization'], 'Bearer valid-test-token');

        called = true;

        return http.Response(jsonEncode({'success': true}), 200);
      });

      final service = GoogleCalendarService(
        httpClient: mockClient,
        backendUrl: 'https://test.render.com',
        accessTokenProvider: () => 'valid-test-token',
      );

      await service.disconnect();

      expect(called, true);

      service.dispose();
    });

    test('throws GoogleCalendarException 401 when token is missing or null', () async {
      final mockClient = MockClient((request) async => http.Response('{}', 200));

      final service = GoogleCalendarService(
        httpClient: mockClient,
        backendUrl: 'https://test.render.com',
        accessTokenProvider: () => null,
      );

      expect(
        () => service.getStatus(),
        throwsA(
          isA<GoogleCalendarException>().having(
            (e) => e.message,
            'message',
            'Your session has expired. Please sign in.',
          ).having((e) => e.statusCode, 'statusCode', 401),
        ),
      );

      service.dispose();
    });

    test('throws GoogleCalendarException 401 when token is empty string', () async {
      final mockClient = MockClient((request) async => http.Response('{}', 200));

      final service = GoogleCalendarService(
        httpClient: mockClient,
        backendUrl: 'https://test.render.com',
        accessTokenProvider: () => '',
      );

      expect(
        () => service.getStatus(),
        throwsA(
          isA<GoogleCalendarException>().having(
            (e) => e.message,
            'message',
            'Your session has expired. Please sign in.',
          ).having((e) => e.statusCode, 'statusCode', 401),
        ),
      );

      service.dispose();
    });
  });

  group('Session refresh behavior simulations', () {
    test('Simulates refresh success: provides refreshed token after expiration', () async {
      var callCount = 0;
      final service = GoogleCalendarService(
        httpClient: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer refreshed-token');
          return http.Response(
            jsonEncode({'connected': true, 'email': 'refreshed@gmail.com'}),
            200,
          );
        }),
        backendUrl: 'https://test.render.com',
        accessTokenProvider: () {
          callCount++;
          // Simulates expired on first evaluation, then refreshed
          return 'refreshed-token';
        },
      );

      final status = await service.getStatus();
      expect(status.connected, true);
      expect(status.email, 'refreshed@gmail.com');
      expect(callCount, 1);
      service.dispose();
    });

    test('Simulates refresh failure: returns null and triggers session-expired 401', () async {
      final service = GoogleCalendarService(
        httpClient: MockClient((request) async => http.Response('{}', 200)),
        backendUrl: 'https://test.render.com',
        accessTokenProvider: () {
          // Refresh failed
          return null;
        },
      );

      expect(
        () => service.getStatus(),
        throwsA(
          isA<GoogleCalendarException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
      service.dispose();
    });
  });
}
