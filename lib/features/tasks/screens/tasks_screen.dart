import 'package:material_ui/material_ui.dart';

import '../widgets/task_alarm_button.dart';
import '../services/task_service.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, this.initialTaskId, this.taskReader});

  final String? initialTaskId;
  final TaskReader? taskReader;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  TaskService? _defaultService;
  final GlobalKey _highlightedTaskKey = GlobalKey();
  TaskService get _service => _defaultService ??= TaskService();
  TaskReader get _taskReader => widget.taskReader ?? _service;

  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String _filter = 'all';
  bool _targetTaskMissing = false;

  Color get orange => Theme.of(context).colorScheme.primary;
  Color get cardColor => Theme.of(context).colorScheme.surface;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await _taskReader.getDailyTasks();
      final targetId = widget.initialTaskId?.trim();
      var targetMissing = false;
      if (targetId != null &&
          targetId.isNotEmpty &&
          !tasks.any((task) => task['id']?.toString() == targetId)) {
        final targetTask = await _taskReader.getTaskById(targetId);
        if (targetTask == null) {
          targetMissing = true;
        } else {
          tasks.add(targetTask);
        }
      }

      if (!mounted) return;

      setState(() {
        _tasks = tasks;
        _targetTaskMissing = targetMissing;
        _loading = false;
      });
      if (!targetMissing && targetId != null && targetId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final targetContext = _highlightedTaskKey.currentContext;
          if (targetContext != null) {
            Scrollable.ensureVisible(
              targetContext,
              duration: const Duration(milliseconds: 350),
              alignment: 0.3,
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _message('Unable to load daily tasks: $e');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isCompleted(Map<String, dynamic> task) {
    return task['is_completed'] == true;
  }

  List<Map<String, dynamic>> get _filteredTasks {
    final today = DateUtils.dateOnly(DateTime.now());

    return _tasks.where((task) {
      final completed = _isCompleted(task);
      final dueValue = task['due_date'];

      final dueDate = dueValue == null
          ? null
          : DateTime.tryParse(dueValue.toString());

      switch (_filter) {
        case 'today':
          return !completed &&
              dueDate != null &&
              DateUtils.isSameDay(dueDate, today);

        case 'upcoming':
          return !completed &&
              dueDate != null &&
              DateUtils.dateOnly(dueDate).isAfter(today);

        case 'completed':
          return completed;

        case 'pending':
          return !completed;

        default:
          return true;
      }
    }).toList();
  }

  Future<void> _openTaskForm() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TaskFormScreen()),
    );

    if (created == true) {
      await _loadTasks();
    }
  }

  Future<void> _toggleTask(Map<String, dynamic> task) async {
    final completed = !_isCompleted(task);

    try {
      await _service.toggleTask(
        taskId: task['id'].toString(),
        completed: completed,
        countForStreak: true,
      );

      await _loadTasks();

      if (mounted) {
        _message(completed ? 'Task completed!' : 'Task reopened.');
      }
    } catch (e) {
      _message('Could not update task: $e');
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Delete "${task['title']}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete the task's alarm before deleting the task itself.
      await TaskAlarmButton.cancelTaskAlarm(task['id'].toString());

      await _service.deleteTask(task['id'].toString());

      await _loadTasks();

      if (mounted) _message('Task deleted.');
    } catch (e) {
      _message('Could not delete task: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _filteredTasks;
    final completed = _tasks.where(_isCompleted).length;
    final pending = _tasks.length - completed;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Daily To-do',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(onPressed: _loadTasks, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openTaskForm,
        backgroundColor: orange,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        color: orange,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_targetTaskMissing) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      child: Text(
                        'This task is no longer available. You can still view your current tasks.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _summaryCard(completed, pending),
                  const SizedBox(height: 20),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('all', 'All'),
                        _filterChip('pending', 'Pending'),
                        _filterChip('today', 'Today'),
                        _filterChip('upcoming', 'Upcoming'),
                        _filterChip('completed', 'Completed'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (tasks.isEmpty) _emptyState() else ...tasks.map(_taskCard),

                  const SizedBox(height: 90),
                ],
              ),
      ),
    );
  }

  Widget _summaryCard(int completed, int pending) {
    final total = _tasks.length;
    final progress = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('TOTAL', total),
              _stat('PENDING', pending),
              _stat('DONE', completed),
            ],
          ),
          const SizedBox(height: 18),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.12),
            color: orange,
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).round()}% completed',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        selectedColor: orange,
        onSelected: (_) {
          setState(() => _filter = value);
        },
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final isNotificationTarget =
        task['id']?.toString() == widget.initialTaskId?.trim();
    final completed = _isCompleted(task);
    final priority = task['priority']?.toString() ?? 'medium';
    final dueDate = task['due_date']?.toString();

    final priorityColor = switch (priority.toLowerCase()) {
      'high' => Theme.of(context).colorScheme.error,
      'low' => Colors.green,
      _ => orange,
    };

    return Card(
      key: isNotificationTarget ? _highlightedTaskKey : null,
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: isNotificationTarget
              ? orange
              : Theme.of(context).colorScheme.outline,
          width: isNotificationTarget ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Checkbox(
              value: completed,
              activeColor: orange,
              onChanged: (_) => _toggleTask(task),
            ),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task['title']?.toString() ?? 'Untitled task',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      decoration: completed ? TextDecoration.lineThrough : null,
                      color: completed
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),

                  if ((task['description'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      task['description'].toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 12,
                    children: [
                      Text(
                        priority.toUpperCase(),
                        style: TextStyle(
                          color: priorityColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (dueDate != null)
                        Text(
                          'Due: $dueDate',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Individual reminder button for this task.
            TaskAlarmButton(
              taskId: task['id'].toString(),
              taskTitle: task['title']?.toString() ?? 'Task',
            ),

            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteTask(task);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete task')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 55),
      child: Column(
        children: [
          Icon(Icons.task_alt, size: 55, color: orange),
          const SizedBox(height: 14),
          const Text(
            'Nothing here yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Add a task and take the next step.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _openTaskForm,
            icon: const Icon(Icons.add),
            label: const Text('Create your first task'),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// CREATE DAILY TASK
// --------------------------------------------------

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = TaskService();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _priority = 'medium';
  DateTime? _dueDate;
  bool _saving = false;

  Color get orange => Theme.of(context).colorScheme.primary;

  Future<void> _pickDueDate() async {
    final today = DateUtils.dateOnly(DateTime.now());

    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? today,
      firstDate: today,
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      setState(() => _dueDate = selected);
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      await _service.createTask(
        title: _titleController.text,
        description: _descriptionController.text,
        priority: _priority,
        dueDate: _dueDate,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save task: $e')));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Daily Task')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'What needs to get done?',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 22),

              TextFormField(
                controller: _titleController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Task title',
                  hintText: 'Example: Complete morning workout',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task title.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 14),

              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                maxLength: 400,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _priority = value);
                  }
                },
              ),

              const SizedBox(height: 12),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due date'),
                subtitle: Text(
                  _dueDate == null
                      ? 'No deadline'
                      : _dueDate!.toIso8601String().split('T').first,
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: _pickDueDate,
              ),

              TextButton(
                onPressed: () {
                  setState(() => _dueDate = null);
                },
                child: const Text('Clear due date'),
              ),

              const SizedBox(height: 25),

              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _saveTask,
                  style: FilledButton.styleFrom(
                    backgroundColor: orange,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: _saving
                      ? CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.onPrimary,
                        )
                      : const Text(
                          'Save Task',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
