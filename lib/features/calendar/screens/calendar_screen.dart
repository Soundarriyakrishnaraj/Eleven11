// lib/features/calendar/screens/calendar_screen.dart

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers/theme_provider.dart';
import '../models/event_model.dart';
import '../services/event_service.dart';
import 'create_edit_event_screen.dart';

enum CalendarViewMode { day, week, month }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final EventService _eventService = EventService();

  CalendarViewMode _viewMode = CalendarViewMode.day;
  DateTime _selectedDate = DateTime.now();
  List<CalendarEvent> _events = [];

  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isGoogleConnected = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _checkGoogleConnection();
    await _fetchEvents();
  }

  Future<void> _checkGoogleConnection() async {
    final connected = await _eventService.isGoogleCalendarConnected();
    if (mounted) {
      setState(() => _isGoogleConnected = connected);
    }
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      DateTime rangeStart;
      DateTime rangeEnd;

      switch (_viewMode) {
        case CalendarViewMode.day:
          rangeStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
          rangeEnd = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
          break;
        case CalendarViewMode.week:
          final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
          rangeStart = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
          rangeEnd = rangeStart.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));
          break;
        case CalendarViewMode.month:
          rangeStart = DateTime(_selectedDate.year, _selectedDate.month, 1);
          rangeEnd = DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59);
          break;
      }

      final list = await _eventService.getEvents(
        startTime: rangeStart,
        endTime: rangeEnd,
      );

      if (mounted) {
        setState(() {
          _events = list;
          _isLoading = false;
        });
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

  Future<void> _pullSync() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      await _eventService.pullSyncFromGoogle();
      await _fetchEvents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendar synced with Google successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _navigateDate(int offset) {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.day:
          _selectedDate = _selectedDate.add(Duration(days: offset));
          break;
        case CalendarViewMode.week:
          _selectedDate = _selectedDate.add(Duration(days: offset * 7));
          break;
        case CalendarViewMode.month:
          _selectedDate = DateTime(
            _selectedDate.year,
            _selectedDate.month + offset,
            _selectedDate.day,
          );
          break;
      }
    });
    _fetchEvents();
  }

  Future<void> _openCreateEvent() async {
    final result = await Navigator.push<CalendarEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditEventScreen(initialDate: _selectedDate),
      ),
    );

    if (result != null) {
      _fetchEvents();
    }
  }

  Future<void> _openEditEvent(CalendarEvent event) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditEventScreen(initialEvent: event),
      ),
    );

    if (result != null) {
      _fetchEvents();
    }
  }

  Widget _buildDateHeader() {
    String title;
    switch (_viewMode) {
      case CalendarViewMode.day:
        title = DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);
        break;
      case CalendarViewMode.week:
        final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        title = '${DateFormat('MMM d').format(startOfWeek)} - ${DateFormat('MMM d, yyyy').format(endOfWeek)}';
        break;
      case CalendarViewMode.month:
        title = DateFormat('MMMM yyyy').format(_selectedDate);
        break;
    }

    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _navigateDate(-1),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedDate = DateTime.now());
                      _fetchEvents();
                    },
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _navigateDate(1),
                ),
              ],
            ),
          ),
          if (!isToday)
            TextButton(
              onPressed: () {
                setState(() => _selectedDate = DateTime.now());
                _fetchEvents();
              },
              child: const Text('Today', style: TextStyle(color: kSignatureOrange)),
            ),
        ],
      ),
    );
  }

  Widget _buildViewSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SegmentedButton<CalendarViewMode>(
        segments: const [
          ButtonSegment(
            value: CalendarViewMode.day,
            label: Text('Day'),
            icon: Icon(Icons.calendar_view_day),
          ),
          ButtonSegment(
            value: CalendarViewMode.week,
            label: Text('Week'),
            icon: Icon(Icons.calendar_view_week),
          ),
          ButtonSegment(
            value: CalendarViewMode.month,
            label: Text('Month'),
            icon: Icon(Icons.calendar_view_month),
          ),
        ],
        selected: {_viewMode},
        onSelectionChanged: (set) {
          setState(() => _viewMode = set.first);
          _fetchEvents();
        },
      ),
    );
  }

  Widget _buildEventCard(CalendarEvent event) {
    final theme = Theme.of(context);

    final timeFormatter = DateFormat('h:mm a');
    final timeStr = event.isAllDay
        ? 'All Day'
        : '${timeFormatter.format(event.startTime.toLocal())} - ${timeFormatter.format(event.endTime.toLocal())}';

    final hasGoogle = event.syncWithGoogle && event.googleEventId != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openEditEvent(event),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: hasGoogle ? Colors.blue : kSignatureOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (hasGoogle)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.sync, size: 16, color: Colors.blue),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (event.location != null && event.location!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.location!,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (event.attendees.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${event.attendees.length} attendee${event.attendees.length > 1 ? "s" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No events scheduled',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "+" to add a meeting or reminder.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openCreateEvent,
            icon: const Icon(Icons.add),
            label: const Text('Add Event'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kSignatureOrange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Calendar & Schedule'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          if (_isGoogleConnected)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              tooltip: 'Sync with Google Calendar',
              onPressed: _isSyncing ? null : _pullSync,
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Event',
            onPressed: _openCreateEvent,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildViewSelector(),
            _buildDateHeader(),
            const Divider(height: 1),
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _pullSync,
                      child: _events.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              itemCount: _events.length,
                              itemBuilder: (ctx, i) => _buildEventCard(_events[i]),
                            ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar_add_event_fab',
        backgroundColor: kSignatureOrange,
        foregroundColor: Colors.white,
        onPressed: _openCreateEvent,
        child: const Icon(Icons.add),
      ),
    );
  }
}
