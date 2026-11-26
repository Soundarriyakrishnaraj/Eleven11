import 'package:material_ui/material_ui.dart';

import '../../calendar/services/google_calendar_service.dart';

/// Settings -> Integrations -> Google Calendar
class GoogleCalendarSettingsScreen extends StatefulWidget {
  const GoogleCalendarSettingsScreen({super.key, this.service});

  final GoogleCalendarService? service;

  @override
  State<GoogleCalendarSettingsScreen> createState() =>
      _GoogleCalendarSettingsScreenState();
}

class _GoogleCalendarSettingsScreenState
    extends State<GoogleCalendarSettingsScreen> {
  late final GoogleCalendarService _service;
  late final bool _ownsService;

  bool _loading = true;
  bool _busy = false;
  bool _connected = false;
  String? _email;
  String _selectedCalendarId = 'primary';
  bool _autoTaskSync = true;
  int _defaultReminderMinutes = 15;
  List<Map<String, dynamic>> _calendars = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? GoogleCalendarService();
    _load();
  }

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _service.getTaskSyncSettings();
      final connected = settings['connected'] == true;
      List<Map<String, dynamic>> cals = [];
      if (connected) {
        try {
          cals = await _service.listCalendars();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _connected = connected;
        _email = settings['email']?.toString();
        _selectedCalendarId =
            settings['selectedCalendarId']?.toString() ?? 'primary';
        _autoTaskSync = settings['autoTaskSync'] != false;
        _defaultReminderMinutes =
            (settings['defaultReminderMinutes'] as num?)?.toInt() ?? 15;
        _calendars = cals;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await _service.startAuthorization(
        onCompleted: (_) async {
          if (mounted) await _load();
        },
        onError: (error) {
          if (mounted) _snack(error);
        },
      );
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _service.disconnect();
      await _load();
      if (mounted) _snack('Disconnected Google Calendar.');
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTasksCalendar() async {
    setState(() => _busy = true);
    try {
      final cal = await _service.createTasksCalendar();
      await _load();
      if (mounted) {
        _snack('Created & selected "${cal['summary'] ?? 'Eleven11 Tasks'}".');
      }
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateSettings({
    String? calendarId,
    String? calendarName,
    bool? autoSync,
    int? reminderMinutes,
  }) async {
    setState(() => _busy = true);
    try {
      await _service.updateTaskSyncSettings(
        selectedCalendarId: calendarId,
        selectedCalendarName: calendarName,
        autoTaskSync: autoSync,
        defaultReminderMinutes: reminderMinutes,
      );
      await _load();
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GOOGLE CALENDAR'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                Card(
                  child: ListTile(
                    leading: Icon(
                      _connected ? Icons.check_circle : Icons.link_off,
                      color: _connected ? Colors.green : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      _connected
                          ? 'Connected Google Account'
                          : 'Not Connected',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _connected
                          ? (_email ?? 'Connected')
                          : 'Connect your personal Google account to sync tasks.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_connected)
                  FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.login),
                    label: const Text('Connect Google Account'),
                  )
                else ...[
                  if (_calendars.isNotEmpty) ...[
                    const Text(
                      'Select Calendar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _calendars.any(
                              (c) => c['id'] == _selectedCalendarId)
                          ? _selectedCalendarId
                          : null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final c in _calendars)
                          DropdownMenuItem<String>(
                            value: c['id'].toString(),
                            child: Text(c['summary'].toString()),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (val) {
                              if (val == null) return;
                              final match = _calendars.firstWhere(
                                (c) => c['id'] == val,
                                orElse: () => {'summary': val},
                              );
                              _updateSettings(
                                calendarId: val,
                                calendarName: match['summary']?.toString(),
                              );
                            },
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _createTasksCalendar,
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Create "Eleven11 Tasks" Calendar'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Automatic Task Sync'),
                    subtitle: const Text(
                      'Sync tasks with date & time to your selected Google Calendar',
                    ),
                    value: _autoTaskSync,
                    onChanged: _busy
                        ? null
                        : (v) => _updateSettings(autoSync: v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _defaultReminderMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Default Reminder',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('No reminder')),
                      DropdownMenuItem(value: 5, child: Text('5 minutes before')),
                      DropdownMenuItem(value: 10, child: Text('10 minutes before')),
                      DropdownMenuItem(value: 15, child: Text('15 minutes before')),
                      DropdownMenuItem(value: 30, child: Text('30 minutes before')),
                      DropdownMenuItem(value: 60, child: Text('1 hour before')),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) _updateSettings(reminderMinutes: v);
                          },
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Share Calendar with Friends',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. Open Google Calendar on web or mobile.\n'
                            '2. Open Settings for your "Eleven11 Tasks" calendar.\n'
                            '3. Go to "Share with specific people or groups" and add your friend\'s email.\n'
                            '4. Set permission to "See all event details".\n\n'
                            'Your friends can view your shared events in Google Calendar without installing Eleven11, and each friend controls their own notification preferences.',
                            style: TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    onPressed: _busy ? null : _disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect Google Calendar'),
                  ),
                ],
              ],
            ),
    );
  }
}
