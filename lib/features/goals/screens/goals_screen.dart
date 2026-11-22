import 'package:material_ui/material_ui.dart';

import '../services/goal_service.dart';
import '../../tasks/services/task_service.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final GoalService _service = GoalService();

  List<Map<String, dynamic>> _goals = [];
  bool _loading = true;
  String _filter = 'all';

  Color get orange => Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  Future<void> _loadGoals() async {
    try {
      final goals = await _service.getGoals();

      if (!mounted) return;

      setState(() {
        _goals = goals;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Unable to load goals: $e');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  List<Map<String, dynamic>> get _filteredGoals {
    if (_filter == 'all') return _goals;

    return _goals.where((goal) => goal['status'] == _filter).toList();
  }

  Future<void> _openGoalForm() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => GoalFormScreen(service: _service)),
    );

    if (created == true) await _loadGoals();
  }

  Future<void> _openGoalTasks(Map<String, dynamic> goal) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoalTasksScreen(
          goalId: goal['id'].toString(),
          goalTitle: goal['title']?.toString() ?? 'Goal',
        ),
      ),
    );

    if (mounted) await _loadGoals();
  }

  Future<void> _changeProgress(Map<String, dynamic> goal) async {
    final current = (goal['progress'] as num?)?.toInt() ?? 0;
    double selected = current.toDouble();

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Update progress'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${selected.round()}%',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: selected,
                min: 0,
                max: 100,
                divisions: 20,
                activeColor: orange,
                onChanged: (value) {
                  setDialogState(() => selected = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected.round()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await _service.updateProgress(
        goalId: goal['id'].toString(),
        progress: result,
      );

      await _loadGoals();

      if (mounted) _message('Goal progress updated.');
    } catch (e) {
      _message('Could not update progress: $e');
    }
  }

  Future<void> _changeStatus(Map<String, dynamic> goal) async {
    final status = goal['status']?.toString() ?? 'active';
    final id = goal['id'].toString();

    try {
      if (status == 'paused') {
        await _service.resumeGoal(id);
      } else {
        await _service.pauseGoal(id);
      }

      await _loadGoals();
    } catch (e) {
      _message('Could not update goal: $e');
    }
  }

  Future<void> _deleteGoal(Map<String, dynamic> goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('Delete "${goal['title']}" permanently?'),
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
      await _service.deleteGoal(goal['id'].toString());
      await _loadGoals();

      if (mounted) _message('Goal deleted.');
    } catch (e) {
      _message('Could not delete goal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = _filteredGoals;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Goals',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(onPressed: _loadGoals, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openGoalForm,
        backgroundColor: orange,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('New Goal'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadGoals,
        color: orange,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryCard(),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('all', 'All'),
                        _filterChip('active', 'Active'),
                        _filterChip('paused', 'Paused'),
                        _filterChip('completed', 'Completed'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (goals.isEmpty) _emptyState() else ...goals.map(_goalCard),
                  const SizedBox(height: 90),
                ],
              ),
      ),
    );
  }

  Widget _summaryCard() {
    final active = _goals.where((g) => g['status'] == 'active').length;
    final completed = _goals.where((g) => g['status'] == 'completed').length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('TOTAL', _goals.length),
          _stat('ACTIVE', active),
          _stat('COMPLETED', completed),
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
    final selected = _filter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: orange,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _goalCard(Map<String, dynamic> goal) {
    final progress = ((goal['progress'] as num?)?.toInt() ?? 0).clamp(0, 100);

    final status = goal['status']?.toString() ?? 'active';
    final targetDate = goal['target_date']?.toString();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openGoalTasks(goal),
      child: Card(
        color: Theme.of(context).colorScheme.surface,
        margin: const EdgeInsets.only(bottom: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal['title']?.toString() ?? 'Untitled goal',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'progress') {
                        _changeProgress(goal);
                      } else if (action == 'status') {
                        _changeStatus(goal);
                      } else if (action == 'delete') {
                        _deleteGoal(goal);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'progress',
                        child: Text('Update progress'),
                      ),
                      if (status != 'completed')
                        PopupMenuItem(
                          value: 'status',
                          child: Text(
                            status == 'paused' ? 'Resume goal' : 'Pause goal',
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete goal'),
                      ),
                    ],
                  ),
                ],
              ),
              if ((goal['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  goal['description'].toString(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '$progress%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress / 100,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                backgroundColor: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.12),
                color: orange,
              ),
              if (targetDate != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Target date: $targetDate',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.checklist, color: orange, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Tap to open goal checklist',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final isCompleted = _filter == 'completed';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 55),
      child: Column(
        children: [
          Icon(
            isCompleted ? Icons.emoji_events_outlined : Icons.flag_outlined,
            size: 55,
            color: orange,
          ),
          const SizedBox(height: 14),
          Text(
            isCompleted
                ? 'Your first victory is waiting!'
                : 'No goals here yet',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isCompleted
                ? 'Complete your first goal and it will appear here. Every small step takes you closer to success.'
                : 'Create a goal and start making progress.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (!isCompleted) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _openGoalForm,
              icon: const Icon(Icons.add),
              label: const Text('Create your first goal'),
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------
// GOAL CHECKLIST SCREEN
// --------------------------------------------------

class GoalTasksScreen extends StatefulWidget {
  const GoalTasksScreen({
    super.key,
    required this.goalId,
    required this.goalTitle,
  });

  final String goalId;
  final String goalTitle;

  @override
  State<GoalTasksScreen> createState() => _GoalTasksScreenState();
}

class _GoalTasksScreenState extends State<GoalTasksScreen> {
  final TaskService _service = TaskService();
  final TextEditingController _titleController = TextEditingController();

  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  bool _saving = false;

  Color get orange => Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await _service.getGoalTasks(widget.goalId);

      if (!mounted) return;

      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Could not load tasks: $e');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addTask() async {
    final title = _titleController.text.trim();

    if (title.isEmpty || _saving) return;

    setState(() => _saving = true);

    try {
      await _service.createTask(title: title, goalId: widget.goalId);

      _titleController.clear();
      await _loadTasks();
    } catch (e) {
      _message('Could not save task: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleTask(Map<String, dynamic> task) async {
    final completed = task['is_completed'] == true;

    try {
      await _service.toggleTask(
        taskId: task['id'].toString(),
        completed: !completed,
      );

      await _loadTasks();
    } catch (e) {
      _message('Could not update task: $e');
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    try {
      await _service.deleteTask(task['id'].toString());
      await _loadTasks();
    } catch (e) {
      _message('Could not delete task: $e');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completed = _tasks
        .where((task) => task['is_completed'] == true)
        .length;

    final total = _tasks.length;
    final progress = total == 0 ? 0.0 : completed / total;

    return Scaffold(
      appBar: AppBar(title: const Text('Goal Checklist')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  widget.goalTitle,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$completed of $total tasks completed'),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 9,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.12),
                          color: orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 8),
                        Text('${(progress * 100).round()}% complete'),
                        if (total > 0 && completed == total) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.emoji_events, color: orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Goal completed! Great work!',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Add a task',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'What needs to be done?',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _addTask(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: _saving ? null : _addTask,
                      style: IconButton.styleFrom(
                        backgroundColor: orange,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimary,
                      ),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Your checklist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (_tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 35),
                    child: Center(
                      child: Text(
                        'No tasks yet. Add your first task above.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  ..._tasks.map((task) {
                    final isDone = task['is_completed'] == true;

                    return Card(
                      color: Theme.of(context).colorScheme.surface,
                      child: ListTile(
                        leading: Checkbox(
                          value: isDone,
                          activeColor: orange,
                          onChanged: (_) => _toggleTask(task),
                        ),
                        title: Text(
                          task['title']?.toString() ?? '',
                          style: TextStyle(
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : null,
                            color: isDone
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => _deleteTask(task),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

// --------------------------------------------------
// CREATE GOAL SCREEN
// --------------------------------------------------

class GoalFormScreen extends StatefulWidget {
  const GoalFormScreen({super.key, required this.service});

  final GoalService service;

  @override
  State<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends State<GoalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  String? _categoryId;
  DateTime? _startDate = DateTime.now();
  DateTime? _targetDate;
  bool _saving = false;
  bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.service.getCategories();

      if (!mounted) return;

      setState(() {
        _categories = categories;
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCategories = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load categories: $e')));
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_targetDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selected == null) return;

    setState(() {
      if (isStart) {
        _startDate = selected;

        if (_targetDate != null && _targetDate!.isBefore(selected)) {
          _targetDate = null;
        }
      } else {
        _targetDate = selected;
      }
    });
  }

  Future<void> _saveGoal() async {
    if (!_formKey.currentState!.validate()) return;

    if (_targetDate != null &&
        _startDate != null &&
        _targetDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Target date cannot be before start date.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.service.createGoal(
        title: _titleController.text,
        description: _descriptionController.text,
        categoryId: _categoryId,
        startDate: _startDate,
        targetDate: _targetDate,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save goal: $e')));
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
      appBar: AppBar(title: const Text('Create Goal')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'What do you want to achieve?',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _titleController,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Goal title',
                  hintText: 'Example: Read 12 books',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a goal title.';
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
                  labelText: 'Why is this goal important? (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              if (_loadingCategories)
                const Center(child: CircularProgressIndicator())
              else if (_categories.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.map((category) {
                    return DropdownMenuItem<String>(
                      value: category['id'].toString(),
                      child: Text(category['name'].toString()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _categoryId = value);
                  },
                ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start date'),
                subtitle: Text(
                  _startDate == null
                      ? 'Not selected'
                      : _startDate!.toLocal().toString().split(' ').first,
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: () => _pickDate(isStart: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Target date'),
                subtitle: Text(
                  _targetDate == null
                      ? 'No deadline'
                      : _targetDate!.toLocal().toString().split(' ').first,
                ),
                trailing: const Icon(Icons.event),
                onTap: () => _pickDate(isStart: false),
              ),
              const SizedBox(height: 25),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _saveGoal,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: _saving
                      ? CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.onPrimary,
                        )
                      : const Text(
                          'Save Goal',
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
