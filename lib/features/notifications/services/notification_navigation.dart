import 'package:material_ui/material_ui.dart';

import '../../alarms/screens/alarm_reminders_screen.dart';
import '../../alarms/screens/alarm_ringing_screen.dart';
import '../../dashboard/dashboard_screen.dart';
import '../../goals/screens/goals_screen.dart';
import '../../motivation/screens/motivation_screen.dart';
import '../../tasks/screens/tasks_screen.dart';
import '../models/notification_model.dart';

class NotificationNavigation {
  NotificationNavigation._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Widget destinationFor({
    required NotificationCategory category,
    Map<String, dynamic> data = const {},
  }) {
    final nestedData = data['data'];
    final routeData = nestedData is Map
        ? <String, dynamic>{...Map<String, dynamic>.from(nestedData), ...data}
        : data;
    final explicitTarget =
        routeData['target']?.toString().toLowerCase() ??
        routeData['route']?.toString().toLowerCase() ??
        routeData['screen']?.toString().toLowerCase();

    // If an active alarm notification is triggered or tapped, route to the full-screen Alarm Ringing interface
    if (explicitTarget == 'alarm' || explicitTarget == 'alarms' || category == NotificationCategory.alarm) {
      if (routeData.containsKey('alarmId') || routeData.containsKey('alarmInstanceId')) {
        return AlarmRingingScreen(payload: routeData);
      }
      return const AlarmRemindersScreen();
    }
    if (explicitTarget == 'task' || explicitTarget == 'tasks') {
      return TasksScreen(
        initialTaskId:
            routeData['taskId']?.toString() ?? routeData['task_id']?.toString(),
      );
    }
    if (explicitTarget == 'goal' || explicitTarget == 'goals') {
      return const GoalsScreen();
    }
    if (explicitTarget == 'motivation' || explicitTarget == 'quotes') {
      return const MotivationScreen();
    }

    switch (category) {
      case NotificationCategory.alarm:
        return const AlarmRemindersScreen();
      case NotificationCategory.task:
        return TasksScreen(
          initialTaskId:
              routeData['taskId']?.toString() ??
              routeData['task_id']?.toString(),
        );
      case NotificationCategory.goal:
        return const GoalsScreen();
      case NotificationCategory.motivation:
        return const MotivationScreen();
      case NotificationCategory.announcement:
      case NotificationCategory.general:
        return const DashboardScreen();
    }
  }

  /// Navigates to the relevant screen based on the notification's category.
  static Future<bool> navigateToTarget({
    BuildContext? context,
    required NotificationCategory category,
    Map<String, dynamic> data = const {},
  }) async {
    final nav = context != null
        ? Navigator.of(context)
        : navigatorKey.currentState;

    if (nav == null) {
      debugPrint('Navigation failed: No NavigatorState available.');
      return false;
    }

    try {
      final destination = destinationFor(category: category, data: data);
      await nav.push(MaterialPageRoute(builder: (_) => destination));

      return true;
    } catch (e) {
      debugPrint('Error navigating from notification: $e');

      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Destination no longer available. Redirecting home.'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      try {
        await nav.push(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );

        return true;
      } catch (_) {
        return false;
      }
    }
  }
}
