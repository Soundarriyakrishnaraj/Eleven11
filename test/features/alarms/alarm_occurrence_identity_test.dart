import 'dart:convert';

import 'package:eleven11/features/alarms/services/alarm_action_handler.dart';
import 'package:eleven11/features/alarms/services/alarm_schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('separate devices can use the same local alarm ID without identity collision', () {
    final firstDeviceAlarm = _alarm(
      id: 1001,
      instanceId: AlarmSchedule.generateInstanceId(),
    );
    final secondDeviceAlarm = _alarm(
      id: 1001,
      instanceId: AlarmSchedule.generateInstanceId(),
    );

    expect(firstDeviceAlarm.id, secondDeviceAlarm.id);
    expect(firstDeviceAlarm.instanceId, isNot(secondDeviceAlarm.instanceId));
    expect(
      AlarmActionHandler.alarmOccurrenceEventId(
        alarmInstanceId: firstDeviceAlarm.instanceId,
        scheduledAt: DateTime.utc(2026, 11, 23, 8),
      ),
      isNot(
        AlarmActionHandler.alarmOccurrenceEventId(
          alarmInstanceId: secondDeviceAlarm.instanceId,
          scheduledAt: DateTime.utc(2026, 11, 23, 8),
        ),
      ),
    );
  });

  test('two scheduled dates for one alarm have distinct occurrence IDs', () {
    final alarm = _alarm(
      id: 1001,
      instanceId: AlarmSchedule.generateInstanceId(),
    );
    final first = AlarmActionHandler.alarmOccurrenceEventId(
      alarmInstanceId: alarm.instanceId,
      scheduledAt: DateTime.utc(2026, 11, 23, 8),
    );
    final nextWeek = AlarmActionHandler.alarmOccurrenceEventId(
      alarmInstanceId: alarm.instanceId,
      scheduledAt: DateTime.utc(2026, 11, 30, 8),
    );

    expect(first, isNot(nextWeek));
  });

  test('recurring planner emits dated one-shot occurrences', () {
    final alarm = _alarm(
      id: 1001,
      instanceId: AlarmSchedule.generateInstanceId(),
    );
    final occurrences = AlarmScheduleService.planUpcomingOccurrences(
      [alarm],
      now: DateTime(2026, 11, 23, 7, 59),
      weeks: 2,
    );

    expect(occurrences, hasLength(6));
    expect(occurrences.first.scheduledAt, DateTime(2026, 11, 23, 8));
    expect(
      occurrences.map((occurrence) => occurrence.sourceEventId).toSet(),
      hasLength(6),
    );
  });

  test(
    'delayed taps retain the scheduled occurrence instead of using today',
    () {
      final scheduledAt = DateTime.utc(2026, 11, 16, 8);
      final payload = AlarmActionHandler.withOccurrenceIdentity({
        'alarmInstanceId': 'c2d5a91e-cf66-4aeb-9869-202ceae3b16c',
        'scheduledAt': scheduledAt.toIso8601String(),
      });

      expect(
        payload['sourceEventId'],
        AlarmActionHandler.alarmOccurrenceEventId(
          alarmInstanceId: 'c2d5a91e-cf66-4aeb-9869-202ceae3b16c',
          scheduledAt: scheduledAt,
        ),
      );
      expect(payload['occurrenceDate'], '2026-11-16');
    },
  );

  test('snooze payloads preserve the original occurrence identity', () {
    const sourceEventId = 'alarm:instance:occurrence';
    final payload = AlarmActionHandler.withOccurrenceIdentity({
      'sourceEventId': sourceEventId,
      'alarmInstanceId': 'c2d5a91e-cf66-4aeb-9869-202ceae3b16c',
      'scheduledAt': '2026-11-16T08:00:00.000Z',
    });

    expect(payload['sourceEventId'], sourceEventId);
  });

  test(
    'legacy alarms receive and persist an instance ID on first load',
    () async {
      SharedPreferences.setMockInitialValues({
        'eleven11_alarm_schedules_user-a': jsonEncode([
          {
            'id': 1001,
            'userId': 'user-a',
            'title': 'Legacy alarm',
            'hour': 8,
            'minute': 0,
            'weekdays': [1, 3, 5],
            'enabled': true,
          },
        ]),
      });

      final service = AlarmScheduleService.instance;
      final migrated = await service.getAlarms('user-a');
      final storedRaw = (await SharedPreferences.getInstance()).getString(
        'eleven11_alarm_schedules_user-a',
      );
      final stored = (jsonDecode(storedRaw!) as List).single as Map;

      expect(migrated.single.instanceId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(stored['instanceId'], migrated.single.instanceId);
      expect(
        (await service.getAlarms('user-a')).single.instanceId,
        migrated.single.instanceId,
      );
    },
  );
}

AlarmSchedule _alarm({required int id, required String instanceId}) =>
    AlarmSchedule(
      id: id,
      instanceId: instanceId,
      userId: 'user-a',
      title: 'Alarm',
      hour: 8,
      minute: 0,
      weekdays: const [1, 3, 5],
    );
