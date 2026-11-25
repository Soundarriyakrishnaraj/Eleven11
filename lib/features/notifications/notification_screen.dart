import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'models/notification_model.dart';
import 'notification_service.dart';
import 'services/notification_navigation.dart';
import 'widgets/notification_preferences_sheet.dart';
import '../../core/providers/theme_provider.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  final NotificationService _service = NotificationService.instance;

  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _outline => Theme.of(context).colorScheme.outline;

  late TabController _tabController;
  List<AppNotification> _allNotifications = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _bulkActionInProgress = false;
  final Set<String> _busyNotificationIds = {};

  StreamSubscription<List<AppNotification>>? _notificationsSub;
  StreamSubscription<int>? _unreadCountSub;

  final List<String> _tabs = ['All', 'Unread', 'Read', 'Reminders', 'Updates'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });

    _listenToStreams();
    _loadNotifications();
  }

  void _listenToStreams() {
    _notificationsSub = _service.notificationsStream.listen((items) {
      if (mounted) {
        setState(() {
          _allNotifications = _sortNotifications(items);
          _loading = false;
        });
      }
    });

    _unreadCountSub = _service.unreadCountStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _notificationsSub?.cancel();
    _unreadCountSub?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications({bool forceRefresh = false}) async {
    try {
      final items = await _service.fetchNotifications(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _allNotifications = _sortNotifications(items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Unable to load notifications: $e');
    }
  }

  Future<void> _markRead(String id) async {
    if (_bulkActionInProgress || !_busyNotificationIds.add(id)) return;
    setState(() {});
    try {
      await _service.markNotificationRead(id);
    } catch (error) {
      _showMessage('Could not update notification: $error');
    } finally {
      _busyNotificationIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _markUnread(String id) async {
    if (_bulkActionInProgress || !_busyNotificationIds.add(id)) return;
    setState(() {});
    try {
      await _service.markNotificationUnread(id);
    } catch (error) {
      _showMessage('Could not update notification: $error');
    } finally {
      _busyNotificationIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _markAllRead() async {
    if (_bulkActionInProgress || _busyNotificationIds.isNotEmpty) return;
    setState(() => _bulkActionInProgress = true);
    try {
      await _service.markAllNotificationsRead();
      _showMessage('All notifications marked as read.');
    } catch (error) {
      _showMessage('Could not update notifications: $error');
    } finally {
      if (mounted) setState(() => _bulkActionInProgress = false);
    }
  }

  Future<void> _deleteNotification(String id) async {
    if (_bulkActionInProgress || !_busyNotificationIds.add(id)) return;
    setState(() {});
    try {
      await _service.deleteNotification(id);
      _showMessage('Notification deleted.');
    } catch (error) {
      _showMessage('Could not delete notification: $error');
    } finally {
      _busyNotificationIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmDeleteNotification(String id) async {
    if (_bulkActionInProgress || _busyNotificationIds.contains(id)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete notification?'),
        content: const Text(
          'This notification will be removed from your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) await _deleteNotification(id);
  }

  Future<void> _clearHistory() async {
    if (_bulkActionInProgress || _busyNotificationIds.isNotEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear Notification History?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will permanently delete your notification history for this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _bulkActionInProgress = true);
    try {
      await _service.clearNotificationHistory();
      _showMessage('Notification history cleared.');
    } catch (error) {
      _showMessage('Could not clear history: $error');
    } finally {
      if (mounted) setState(() => _bulkActionInProgress = false);
    }
  }

  void _openPreferences() {
    NotificationPreferencesSheet.show(context);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: _surface,
      ),
    );
  }

  Future<void> _handleNotificationTap(AppNotification notification) async {
    if (!notification.isRead) {
      await _markRead(notification.id);
    }

    if (!mounted) return;

    await NotificationNavigation.navigateToTarget(
      context: context,
      category: notification.category,
      data: notification.data,
    );
  }

  List<AppNotification> _sortNotifications(
    Iterable<AppNotification> notifications,
  ) {
    return notifications.toList()..sort((a, b) {
      final byCreatedAt = b.createdAt.compareTo(a.createdAt);
      return byCreatedAt != 0 ? byCreatedAt : a.id.compareTo(b.id);
    });
  }

  List<AppNotification> _getFilteredNotifications(int tabIndex) {
    List<AppNotification> list;

    switch (tabIndex) {
      case 1: // Unread
        list = _allNotifications.where((n) => !n.isRead).toList();
        break;
      case 2: // Read
        list = _allNotifications.where((n) => n.isRead).toList();
        break;
      case 3: // Reminders
        list = _allNotifications.where((n) {
          return n.category == NotificationCategory.alarm ||
              n.category == NotificationCategory.task ||
              n.category == NotificationCategory.goal;
        }).toList();
        break;
      case 4: // Updates
        list = _allNotifications.where((n) {
          return n.category == NotificationCategory.motivation ||
              n.category == NotificationCategory.announcement ||
              n.category == NotificationCategory.general;
        }).toList();
        break;
      case 0: // All
      default:
        list = _allNotifications;
        break;
    }

    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((n) {
        return n.title.toLowerCase().contains(query) ||
            n.body.toLowerCase().contains(query) ||
            n.category.displayName.toLowerCase().contains(query);
      }).toList();
    }

    return list;
  }

  Color _categoryColor(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.alarm:
        return kSignatureOrange;
      case NotificationCategory.task:
        return const Color(0xFF10B981); // Emerald Green
      case NotificationCategory.goal:
        return const Color(0xFF06B6D4); // Cyan
      case NotificationCategory.motivation:
        return const Color(0xFFFBBF24); // Amber
      case NotificationCategory.announcement:
        return const Color(0xFFFF5722); // Deep Coral
      case NotificationCategory.general:
        return const Color(0xFF9CA3AF); // Muted
    }
  }

  IconData _categoryIcon(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.alarm:
        return Icons.alarm;
      case NotificationCategory.task:
        return Icons.check_circle_outline;
      case NotificationCategory.goal:
        return Icons.flag_outlined;
      case NotificationCategory.motivation:
        return Icons.lightbulb_outline;
      case NotificationCategory.announcement:
        return Icons.campaign_outlined;
      case NotificationCategory.general:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _allNotifications.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'NOTIFICATIONS',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            fontSize: 18,
          ),
        ),
        actions: [
          if (unreadCount > 0)
            IconButton(
              icon: Icon(
                Icons.done_all,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Mark all as read',
              onPressed: _bulkActionInProgress ? null : _markAllRead,
            ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            color: _surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              if (value == 'read') _markAllRead();
              if (value == 'clear') _clearHistory();
              if (value == 'settings') _openPreferences();
            },
            itemBuilder: (context) => [
              if (unreadCount > 0 && !_bulkActionInProgress)
                PopupMenuItem(
                  value: 'read',
                  child: Row(
                    children: [
                      Icon(
                        Icons.mark_email_read_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Mark all as read',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(
                      Icons.tune,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Preferences',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (_allNotifications.isNotEmpty && !_bulkActionInProgress)
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_sweep_outlined,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Clear history',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              indicator: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Theme.of(context).colorScheme.onPrimary,
              unselectedLabelColor: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _accent,
        backgroundColor: _surface,
        onRefresh: () => _loadNotifications(forceRefresh: true),
        child: Column(
          children: [
            // Header stats banner
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        unreadCount > 0
                            ? '$unreadCount UNREAD'
                            : 'ALL CAUGHT UP',
                        style: TextStyle(
                          color: unreadCount > 0
                              ? _accent
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${_allNotifications.length} TOTAL',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Search notifications',
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: Icon(
                            Icons.close,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                  filled: true,
                  fillColor: _surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),

            // Tab Views
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(_accent),
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: List.generate(
                        _tabs.length,
                        (index) => _buildNotificationList(index),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationList(int tabIndex) {
    final filtered = _getFilteredNotifications(tabIndex);

    if (filtered.isEmpty) {
      return _buildEmptyState(tabIndex);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final notification = filtered[index];
        return _buildNotificationCard(notification);
      },
    );
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final isUnread = !notification.isRead;
    final isBusy =
        _bulkActionInProgress || _busyNotificationIds.contains(notification.id);
    final catColor = _categoryColor(notification.category);
    final catIcon = _categoryIcon(notification.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnread ? _accent : _outline,
          width: isUnread ? 1.4 : 1.0,
        ),
        boxShadow: isUnread
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isBusy ? null : () => _handleNotificationTap(notification),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Icon Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: catColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(catIcon, color: catColor, size: 22),
                ),
                const SizedBox(width: 14),

                // Content Body
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category Tag & Relative Time
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              notification.category.displayName.toUpperCase(),
                              style: TextStyle(
                                color: catColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Text(
                            notification.formattedTime,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Notification Title
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 15,
                                fontWeight: isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isUnread) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          PopupMenuButton<String>(
                            enabled: !isBusy,
                            tooltip: 'Notification actions',
                            icon: Icon(
                              Icons.more_horiz,
                              color: isBusy
                                  ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.3)
                                  : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                            ),
                            color: _surface,
                            onSelected: (action) {
                              if (action == 'read') {
                                _markRead(notification.id);
                              } else if (action == 'unread') {
                                _markUnread(notification.id);
                              } else if (action == 'delete') {
                                _confirmDeleteNotification(notification.id);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: isUnread ? 'read' : 'unread',
                                child: Text(
                                  isUnread ? 'Mark as read' : 'Mark as unread',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Notification Body
                      Text(
                        notification.body,
                        style: TextStyle(
                          color: isUnread
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.35,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),

                      // Destination Action Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _getActionLabel(notification.category),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: _accent,
                            size: 10,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getActionLabel(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.alarm:
        return 'View Alarms';
      case NotificationCategory.task:
        return 'View Tasks';
      case NotificationCategory.goal:
        return 'View Goals';
      case NotificationCategory.motivation:
        return 'View Motivation';
      case NotificationCategory.announcement:
      case NotificationCategory.general:
        return 'Open';
    }
  }

  Widget _buildEmptyState(int tabIndex) {
    String title;
    String subtitle;
    IconData icon;

    if (_searchQuery.trim().isNotEmpty) {
      title = 'No matching notifications';
      subtitle = 'Try a different search term.';
      icon = Icons.search_off;
    } else {
      switch (tabIndex) {
        case 1:
          title = 'No unread notifications';
          subtitle = 'New notifications will appear here.';
          icon = Icons.mark_email_read_outlined;
          break;
        case 2:
          title = 'No read notifications';
          subtitle = 'Notifications you have reviewed will be kept here.';
          icon = Icons.mark_email_read_outlined;
          break;
        case 3:
          title = 'No reminders yet';
          subtitle = 'Task, goal and alarm notifications will appear here.';
          icon = Icons.alarm_off_outlined;
          break;
        case 4:
          title = 'No updates yet';
          subtitle = 'Motivation and announcements will appear here.';
          icon = Icons.campaign_outlined;
          break;
        case 0:
        default:
          title = 'You are all caught up!';
          subtitle = 'No notifications to display right now. Check back later.';
          icon = Icons.notifications_none_outlined;
          break;
      }
    }

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surface,
                shape: BoxShape.circle,
                border: Border.all(color: _outline),
              ),
              child: Icon(
                icon,
                color: _accent.withValues(alpha: 0.6),
                size: 56,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                side: BorderSide(color: _accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
              onPressed: () => _loadNotifications(forceRefresh: true),
            ),
          ],
        ),
      ),
    );
  }
}
