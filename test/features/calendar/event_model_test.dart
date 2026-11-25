// test/features/calendar/event_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:eleven11/features/calendar/models/event_model.dart';
import 'package:eleven11/features/calendar/services/uuid_util.dart';

void main() {
  group('UuidUtil Tests', () {
    test('generateV4 generates valid RFC 4122 version 4 UUIDs', () {
      final uuid = UuidUtil.generateV4();
      expect(uuid.length, 36);
      expect(UuidUtil.isValidUuid(uuid), isTrue);
      // Check 13th character is '4' (version 4)
      expect(uuid[14], '4');
      // Check 17th character is in [8, 9, a, b]
      expect(['8', '9', 'a', 'b', 'A', 'B'].contains(uuid[19]), isTrue);
    });

    test('generateV4 generates distinct values', () {
      final id1 = UuidUtil.generateV4();
      final id2 = UuidUtil.generateV4();
      expect(id1, isNot(equals(id2)));
    });

    test('isValidUuid correctly rejects empty or invalid strings', () {
      expect(UuidUtil.isValidUuid(''), isFalse);
      expect(UuidUtil.isValidUuid('not-a-uuid'), isFalse);
      expect(UuidUtil.isValidUuid(null), isFalse);
      expect(UuidUtil.isValidUuid('12345678-1234-4234-8234-123456789012'), isTrue);
    });
  });

  group('CalendarEvent Model Tests', () {
    final now = DateTime.now();

    test('withValidIdentifiers assigns UUID v4 and stable idempotency key to empty new event', () {
      final newEvent = CalendarEvent(
        id: '',
        userId: 'test-user-uuid',
        title: 'Team Sync',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
      );

      final prepared = newEvent.withValidIdentifiers();

      expect(prepared.id.isNotEmpty, isTrue);
      expect(UuidUtil.isValidUuid(prepared.id), isTrue);
      expect(prepared.idempotencyKey, equals(prepared.id));
      expect(prepared.idempotencyKey!.length, inInclusiveRange(8, 200));
    });

    test('withValidIdentifiers preserves existing valid UUID and stable idempotency key', () {
      const existingId = 'a0000000-0000-4000-8000-000000000001';
      const existingKey = 'custom-stable-key-12345';

      final existingEvent = CalendarEvent(
        id: existingId,
        idempotencyKey: existingKey,
        userId: 'test-user-uuid',
        title: 'Existing Event',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
      );

      final prepared = existingEvent.withValidIdentifiers();

      expect(prepared.id, equals(existingId));
      expect(prepared.idempotencyKey, equals(existingKey));
    });

    test('Multiple calls to withValidIdentifiers are idempotent on retries', () {
      final newEvent = CalendarEvent(
        id: '',
        userId: 'test-user-uuid',
        title: 'Retry Event',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
      );

      final firstPass = newEvent.withValidIdentifiers();
      final retryPass = firstPass.withValidIdentifiers();

      expect(firstPass.id, equals(retryPass.id));
      expect(firstPass.idempotencyKey, equals(retryPass.idempotencyKey));
    });

    test('toBackendSyncPayload formats payload correctly for backend API', () {
      final event = CalendarEvent(
        id: 'b0000000-0000-4000-8000-000000000002',
        idempotencyKey: 'idemp-key-b0000002',
        userId: 'test-user-uuid',
        title: 'Product Review',
        description: 'Q4 roadmap',
        location: 'Virtual',
        startTime: DateTime.utc(2026, 11, 24, 15, 0),
        endTime: DateTime.utc(2026, 11, 24, 16, 0),
        timezone: 'UTC',
        isAllDay: false,
        reminderMinutes: 30,
        attendees: [
          {'email': 'colleague@example.com'},
        ],
      );

      final payload = event.toBackendSyncPayload();

      expect(payload['id'], equals('b0000000-0000-4000-8000-000000000002'));
      expect(payload['idempotencyKey'], equals('idemp-key-b0000002'));
      expect(payload['title'], equals('Product Review'));
      expect(payload['startTime'], '2026-11-24T15:00:00.000Z');
      expect(payload['endTime'], '2026-11-24T16:00:00.000Z');
      expect(payload['reminderMinutes'], 30);
      expect(payload['attendees'], hasLength(1));
    });

    test('toBackendSyncPayload formats all-day events as YYYY-MM-DD', () {
      final allDayEvent = CalendarEvent(
        id: 'c0000000-0000-4000-8000-000000000003',
        userId: 'test-user-uuid',
        title: 'Holiday',
        startTime: DateTime(2026, 12, 25),
        endTime: DateTime(2026, 12, 26),
        isAllDay: true,
      ).withValidIdentifiers();

      final payload = allDayEvent.toBackendSyncPayload();
      expect(payload['startTime'], '2026-12-25');
      expect(payload['endTime'], '2026-12-26');
      expect(payload['isAllDay'], isTrue);
    });
  });
}
