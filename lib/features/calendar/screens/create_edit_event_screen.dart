// lib/features/calendar/screens/create_edit_event_screen.dart

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers/theme_provider.dart';
import '../models/event_model.dart';
import '../../badges/badge_service.dart';
import '../services/event_service.dart';

class CreateEditEventScreen extends StatefulWidget {
  const CreateEditEventScreen({
    super.key,
    this.initialEvent,
    this.initialDate,
  });

  final CalendarEvent? initialEvent;
  final DateTime? initialDate;

  @override
  State<CreateEditEventScreen> createState() => _CreateEditEventScreenState();
}

class _CreateEditEventScreenState extends State<CreateEditEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final EventService _eventService = EventService();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _attendeeController;

  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;

  bool _isAllDay = false;
  bool _syncWithGoogle = true;
  int _reminderMinutes = 15;
  List<String> _attendeeEmails = [];

  bool _isLoading = false;
  bool _isGoogleConnected = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final event = widget.initialEvent;
    final baseDate = widget.initialDate ?? DateTime.now();

    _titleController = TextEditingController(text: event?.title ?? '');
    _descriptionController =
        TextEditingController(text: event?.description ?? '');
    _locationController = TextEditingController(text: event?.location ?? '');
    _attendeeController = TextEditingController();

    if (event != null) {
      _startDate = event.startTime.toLocal();
      _startTime = TimeOfDay.fromDateTime(_startDate);
      _endDate = event.endTime.toLocal();
      _endTime = TimeOfDay.fromDateTime(_endDate);
      _isAllDay = event.isAllDay;
      _syncWithGoogle = event.syncWithGoogle;
      _reminderMinutes = event.reminderMinutes;
      _attendeeEmails = event.attendees
          .map((a) => (a['email'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      _startDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 0);
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 10, 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
    }

    _checkGoogleConnection();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _attendeeController.dispose();
    super.dispose();
  }

  Future<void> _checkGoogleConnection() async {
    final connected = await _eventService.isGoogleCalendarConnected();
    if (mounted) {
      setState(() {
        _isGoogleConnected = connected;
        if (!connected) {
          _syncWithGoogle = false;
        }
      });
    }
  }

  DateTime _combineDateTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _addAttendee() {
    final email = _attendeeController.text.trim();
    if (email.isEmpty) return;

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    if (!_attendeeEmails.contains(email)) {
      setState(() {
        _attendeeEmails.add(email);
        _attendeeController.clear();
      });
    }
  }

  void _removeAttendee(String email) {
    setState(() {
      _attendeeEmails.remove(email);
    });
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    DateTime finalStart;
    DateTime finalEnd;

    if (_isAllDay) {
      finalStart = DateTime(_startDate.year, _startDate.month, _startDate.day);
      finalEnd = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
    } else {
      finalStart = _combineDateTime(_startDate, _startTime);
      finalEnd = _combineDateTime(_endDate, _endTime);

      if (!finalEnd.isAfter(finalStart)) {
        setState(() {
          _errorMessage = 'End time must be after start time.';
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = _eventService.currentUserId;
      if (userId == null) {
        throw const EventServiceException('User not authenticated.');
      }

      final existing = widget.initialEvent;
      final newEvent = CalendarEvent(
        id: (existing?.id != null && existing!.id.isNotEmpty)
            ? existing.id
            : '',
        idempotencyKey: existing?.idempotencyKey,
        userId: userId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        startTime: finalStart,
        endTime: finalEnd,
        isAllDay: _isAllDay,
        syncWithGoogle: _syncWithGoogle && _isGoogleConnected,
        googleEventId: existing?.googleEventId,
        reminderMinutes: _reminderMinutes,
        attendees: _attendeeEmails.map((e) => {'email': e}).toList(),
        status: existing?.status ?? 'confirmed',
        syncStatus: _syncWithGoogle ? 'pending' : 'synced',
      ).withValidIdentifiers();

      final saved = await _eventService.saveEvent(newEvent);
      BadgeService.notifyChanged();
      if (mounted) {
        Navigator.pop(context, saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteEvent() async {
    final event = widget.initialEvent;
    if (event == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text(
          'Are you sure you want to delete this event? '
          'If synced, it will also be removed from Google Calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await _eventService.deleteEvent(event);
      BadgeService.notifyChanged();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initialEvent != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Event' : 'New Event'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _isLoading ? null : _deleteEvent,
            ),
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, color: kSignatureOrange),
            onPressed: _isLoading ? null : _saveEvent,
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),

              // Title
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Event Title *',
                  hintText: 'e.g. Strategy Review, Dentist Appointment',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Title is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Location
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'e.g. Conference Room A, Google Meet',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add details, agenda, or notes',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // All-Day Switch
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: kSignatureOrange,
                title: const Text('All-day Event'),
                value: _isAllDay,
                onChanged: (val) => setState(() => _isAllDay = val),
              ),
              const Divider(height: 24),

              // Starts
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 20),
                          const SizedBox(width: 8),
                          const Text('Starts', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.calendar_today, size: 14),
                            label: Text(DateFormat('EEE, MMM d, y').format(_startDate)),
                            onPressed: () => _pickDate(true),
                          ),
                          if (!_isAllDay)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.schedule, size: 14),
                              label: Text(_startTime.format(context)),
                              onPressed: () => _pickTime(true),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Ends
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.more_time, size: 20),
                          const SizedBox(width: 8),
                          const Text('Ends', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.calendar_today, size: 14),
                            label: Text(DateFormat('EEE, MMM d, y').format(_endDate)),
                            onPressed: () => _pickDate(false),
                          ),
                          if (!_isAllDay)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.schedule, size: 14),
                              label: Text(_endTime.format(context)),
                              onPressed: () => _pickTime(false),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),

              // Reminder Minutes
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Reminder'),
                trailing: DropdownButton<int>(
                  value: _reminderMinutes,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('None')),
                    DropdownMenuItem(value: 5, child: Text('5 minutes before')),
                    DropdownMenuItem(value: 15, child: Text('15 minutes before')),
                    DropdownMenuItem(value: 30, child: Text('30 minutes before')),
                    DropdownMenuItem(value: 60, child: Text('1 hour before')),
                    DropdownMenuItem(value: 1440, child: Text('1 day before')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _reminderMinutes = val);
                  },
                ),
              ),
              const Divider(height: 24),

              // Google Calendar Sync Toggle
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: kSignatureOrange,
                title: Row(
                  children: [
                    const Icon(Icons.sync, size: 20),
                    const SizedBox(width: 8),
                    const Text('Sync with Google Calendar'),
                  ],
                ),
                subtitle: Text(
                  _isGoogleConnected
                      ? 'Two-way sync is active with your Google account.'
                      : 'Google Calendar is not connected. Connect in Account Settings.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isGoogleConnected ? null : Colors.grey,
                  ),
                ),
                value: _syncWithGoogle && _isGoogleConnected,
                onChanged: _isGoogleConnected
                    ? (val) => setState(() => _syncWithGoogle = val)
                    : null,
              ),
              const Divider(height: 24),

              // Attendees / Participants
              Text(
                'Attendees / Participants',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _attendeeController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'Enter attendee email',
                        prefixIcon: Icon(Icons.person_add_outlined),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onSubmitted: (_) => _addAttendee(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addAttendee,
                    icon: const Icon(Icons.add_circle, color: kSignatureOrange),
                  ),
                ],
              ),
              if (_attendeeEmails.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _attendeeEmails.map((email) {
                    return Chip(
                      label: Text(email, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => _removeAttendee(email),
                      deleteIcon: const Icon(Icons.close, size: 16),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
