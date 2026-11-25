import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_text.dart';
import '../services/admin_service.dart';
import 'admin_users_sheet_screen.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.adminService});

  final AdminService? adminService;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final AdminService _adminService;
  late final bool _ownsService;

  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  final List<Map<String, dynamic>> _users = [];
  int _page = 1;
  int _totalUsers = 0;
  bool _hasMore = false;
  String _source = '';
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.adminService == null;
    _adminService = widget.adminService ?? AdminService();
    _fetchUsers(reset: true);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    if (_ownsService) {
      _adminService.dispose();
    }
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _fetchUsers(reset: true);
      }
    });
  }

  Future<void> _fetchUsers({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _page = 1;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final result = await _adminService.fetchUsers(
        query: _searchController.text.trim(),
        page: reset ? 1 : _page + 1,
        limit: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _users
            ..clear()
            ..addAll(result.users);
        } else {
          final existingIds = _users.map((u) => u['id']?.toString()).toSet();
          for (final u in result.users) {
            final id = u['id']?.toString();
            if (id != null && !existingIds.contains(id)) {
              _users.add(u);
              existingIds.add(id);
            }
          }
        }
        _page = result.page;
        _totalUsers = result.total;
        _hasMore = result.hasMore;
        _source = result.source;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _showUserDetail(Map<String, dynamic> user) {
    final createdAt = user['created_at'] != null
        ? DateFormat('yMMMd, HH:mm').format(DateTime.parse(user['created_at']).toLocal())
        : 'N/A';
    final userId = user['id']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppText(
                  user['username'] ?? user['full_name'] ?? 'User Details',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'User UUID', value: userId.isEmpty ? 'N/A' : userId),
                _DetailRow(label: 'Username', value: user['username'] ?? 'Not set'),
                _DetailRow(label: 'Full Name', value: user['full_name'] ?? 'Not specified'),
                _DetailRow(label: 'Email', value: user['email']?.toString() ?? 'Not available'),
                _DetailRow(
                  label: 'Date of Birth',
                  value: user['date_of_birth'] == null
                      ? 'Not provided'
                      : DateFormat('d MMM yyyy').format(DateTime.parse(user['date_of_birth'].toString())),
                ),
                _DetailRow(label: 'Timezone', value: user['tz'] ?? 'UTC'),
                _DetailRow(label: 'Registered', value: createdAt),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                AppText(
                  'LOGIN, LOGOUT & SESSION HISTORY',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<AdminUserActivityResult>(
                  future: _adminService.fetchUserActivity(userId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Unable to load history: ${snapshot.error}',
                          style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                        ),
                      );
                    }

                    final result = snapshot.data;
                    final events = result?.events ?? [];
                    final tableAvailable = result?.tableAvailable ?? false;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!tableAvailable)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Server login_history table is pending Migration 016 approval. Showing only locally cached events on this device (if any).',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (events.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'No login or logout events recorded yet for this user.',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: events.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final ev = events[idx];
                              final eventType = (ev['event_type'] ?? 'login').toString();
                              final rawTs = (ev['occurred_at'] ?? ev['logged_in_at'] ?? ev['timestamp'])?.toString();
                              final timeStr = rawTs != null
                                  ? DateFormat('yMMMd, HH:mm:ss').format(DateTime.parse(rawTs).toLocal())
                                  : '—';

                              final IconData icon;
                              final Color badgeColor;
                              final String title;
                              final String badgeText;

                              if (eventType == 'logout') {
                                icon = Icons.logout_rounded;
                                badgeColor = Colors.orange;
                                title = 'User Logged Out';
                                badgeText = 'LOGOUT';
                              } else if (eventType == 'session_expired') {
                                icon = Icons.timer_off_outlined;
                                badgeColor = Colors.redAccent;
                                title = 'Session Expired';
                                badgeText = 'EXPIRED';
                              } else {
                                icon = Icons.login_rounded;
                                badgeColor = Colors.green;
                                title = 'User Logged In';
                                badgeText = 'LOGIN';
                              }

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(icon, size: 18, color: badgeColor),
                                ),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  timeStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: badgeColor,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const AppText('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const AppText('USER MANAGEMENT'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'View in Excel sheet',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminUsersSheetScreen(adminService: _adminService),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchUsers(reset: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by username, full name, or UUID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _fetchUsers(reset: true);
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (!_isLoading && _errorMessage == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppText(
                    'Showing ${_users.length} of $_totalUsers unique users',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_source.isNotEmpty)
                    AppText(
                      _source == 'backend' ? 'Admin API' : 'Direct DB',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _errorMessage!,
                                style: TextStyle(color: colorScheme.error),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => _fetchUsers(reset: true),
                                child: const AppText('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _users.isEmpty
                        ? const Center(child: AppText('No users found.'))
                        : RefreshIndicator(
                            onRefresh: () => _fetchUsers(reset: true),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(
                                        colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                      ),
                                      columns: const [
                                        DataColumn(label: AppText('USER', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: AppText('FULL NAME', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: AppText('EMAIL', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: AppText('DOB', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: AppText('UUID', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: AppText('TIMEZONE', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: AppText('REGISTERED', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: AppText('HISTORY', style: TextStyle(fontWeight: FontWeight.bold))),
                                      ],
                                      rows: _users.map((user) {
                                        final username = (user['username'] ?? 'Anonymous').toString();
                                        final fullName = (user['full_name'] ?? '—').toString();
                                        final id = (user['id'] ?? '').toString();
                                        final shortId = id.length > 8 ? '${id.substring(0, 8)}…' : id;
                                        final tz = (user['tz'] ?? 'UTC').toString();
                                        final date = user['created_at'] != null
                                            ? DateFormat('MMM d, y').format(DateTime.parse(user['created_at']).toLocal())
                                            : '—';

                                        return DataRow(
                                          onSelectChanged: (_) => _showUserDetail(user),
                                          cells: [
                                            DataCell(
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 14,
                                                    backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                                                    child: Text(
                                                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                                                      style: TextStyle(
                                                        color: colorScheme.primary,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(username, style: const TextStyle(fontWeight: FontWeight.w600)),
                                                ],
                                              ),
                                            ),
                                            DataCell(Text(fullName)),
                                            DataCell(Text((user['email'] ?? '—').toString())),
                                            DataCell(Text(user['date_of_birth'] == null
                                                ? '—'
                                                : DateFormat('d MMM yyyy').format(DateTime.parse(user['date_of_birth'].toString())))),
                                            DataCell(Text(shortId, style: const TextStyle(fontSize: 11))),
                                            DataCell(Text(tz)),
                                            DataCell(Text(date)),
                                            DataCell(
                                              IconButton(
                                                icon: const Icon(Icons.history_rounded, size: 20),
                                                tooltip: 'View Login/Logout History',
                                                onPressed: () => _showUserDetail(user),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  if (_hasMore) ...[
                                    const SizedBox(height: 16),
                                    Center(
                                      child: OutlinedButton.icon(
                                        onPressed: _isLoadingMore
                                            ? null
                                            : () => _fetchUsers(reset: false),
                                        icon: _isLoadingMore
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.expand_more),
                                        label: AppText(
                                          _isLoadingMore ? 'Loading...' : 'Load More Users',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: AppText(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
