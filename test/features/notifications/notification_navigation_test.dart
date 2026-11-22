import 'package:eleven11/features/notifications/models/notification_model.dart';
import 'package:eleven11/features/notifications/services/notification_navigation.dart';
import 'package:eleven11/features/tasks/screens/tasks_screen.dart';
import 'package:eleven11/features/tasks/services/task_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('task notification destination retains task ID from route data', () {
    final destination = NotificationNavigation.destinationFor(
      category: NotificationCategory.task,
      data: {
        'type': 'task',
        'data': {'taskId': 'task-123'},
      },
    );

    expect(destination, isA<TasksScreen>());
    expect((destination as TasksScreen).initialTaskId, 'task-123');
  });

  testWidgets('a deleted task shows a safe Tasks screen fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          initialTaskId: 'deleted-task',
          taskReader: _MissingTaskReader(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This task is no longer available. You can still view your current tasks.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nothing here yet'), findsOneWidget);
  });
}

class _MissingTaskReader implements TaskReader {
  @override
  Future<List<Map<String, dynamic>>> getDailyTasks() async => [];

  @override
  Future<Map<String, dynamic>?> getTaskById(String taskId) async => null;
}
