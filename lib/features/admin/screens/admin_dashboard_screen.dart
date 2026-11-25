import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_text.dart';
import '../services/admin_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.adminService});

  final AdminService? adminService;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminService _adminService;
  late final bool _ownsService;

  bool _isLoading = true;
  String? _errorMessage;
  bool _isAuthorized = false;
  AdminMetrics? _metrics;

  RealtimeChannel? _realtimeChannel;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.adminService == null;
    _adminService = widget.adminService ?? AdminService();
    _checkAuthAndLoadMetrics();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
    }
    if (_ownsService) {
      _adminService.dispose();
    }
    super.dispose();
  }

  void _setupRealtimeAndAutoRefresh() {
    if (_realtimeChannel != null) return;

    try {
      final client = Supabase.instance.client;
      _realtimeChannel = client
          .channel('admin_dashboard_live_metrics')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'profiles',
            callback: (_) => _refreshMetricsSilently(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'events',
            callback: (_) => _refreshMetricsSilently(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_feedback',
            callback: (_) => _refreshMetricsSilently(),
          )
          .subscribe();
    } catch (_) {
      // Realtime may be unavailable in tests or offline; periodic refresh covers it.
    }

    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshMetricsSilently(),
    );
  }

  Future<void> _refreshMetricsSilently() async {
    if (!mounted || !_isAuthorized) return;
    try {
      final metrics = await _adminService.fetchMetrics();
      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _errorMessage = null;
      });
    } catch (_) {}
  }

  Future<void> _checkAuthAndLoadMetrics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authorized = await _adminService.isCurrentUserAuthorizedAdmin();
      if (!authorized) {
        if (mounted) {
          setState(() {
            _isAuthorized = false;
            _isLoading = false;
            _errorMessage =
                'Unauthorized access. Administrator privileges required.';
          });
        }
        return;
      }

      _isAuthorized = true;
      final metrics = await _adminService.fetchMetrics();

      if (mounted) {
        setState(() {
          _metrics = metrics;
          _isLoading = false;
        });
        _setupRealtimeAndAutoRefresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  String _formatNullableCount(int? value) {
    if (value == null) return '—';
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const AppText('ADMIN PANEL')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAuthorized) {
      return Scaffold(
        appBar: AppBar(title: const AppText('ACCESS DENIED')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 64, color: colorScheme.error),
                const SizedBox(height: 16),
                AppText(
                  'Administrator Privileges Required',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                AppText(
                  _errorMessage ??
                      'Your account is not registered in the administrator allowlist.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final metrics = _metrics;
    if (metrics == null) {
      return Scaffold(
        appBar: AppBar(title: const AppText('ADMIN DASHBOARD')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 52, color: colorScheme.error),
                const SizedBox(height: 12),
                AppText(
                  _errorMessage ?? 'Unable to load live admin metrics.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _checkAuthAndLoadMetrics,
                  icon: const Icon(Icons.refresh),
                  label: const AppText('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final refreshedAt = DateFormat('HH:mm:ss').format(metrics.generatedAt.toLocal());
    final missingActivityTables =
        !metrics.presenceAvailable || !metrics.loginHistoryAvailable;

    return Scaffold(
      appBar: AppBar(
        title: const AppText('ADMIN DASHBOARD'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Metrics',
            onPressed: _checkAuthAndLoadMetrics,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _checkAuthAndLoadMetrics,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // LIVE STATUS BAR
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    metrics.source == 'backend'
                        ? Icons.cloud_done_outlined
                        : Icons.storage_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppText(
                      metrics.source == 'backend'
                          ? 'Live DB via Admin API • Updated $refreshedAt'
                          : 'Direct Supabase Query • Updated $refreshedAt',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (missingActivityTables) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppText(
                        'Activity presence / login history tables are pending Migration 016 approval. Unavailable metrics show "—" rather than estimated values.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // USER METRICS GRID
            AppText(
              'USER METRICS',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'Total Users',
                    value: '${metrics.totalUsers}',
                    icon: Icons.people_alt_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    title: 'Active (15m)',
                    value: _formatNullableCount(metrics.activeLast15Min),
                    icon: Icons.bolt_outlined,
                    valueColor: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'Today Reg.',
                    value: '+${metrics.registrationsToday}',
                    icon: Icons.person_add_alt_1_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'Week Reg.',
                    value: '+${metrics.registrationsThisWeek}',
                    icon: Icons.date_range_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'Month Reg.',
                    value: '+${metrics.registrationsThisMonth}',
                    icon: Icons.calendar_month_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ACTIVITY STATS
            AppText(
              'ACTIVITY STATS (DAU / WAU / MAU)',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'DAU',
                    value: _formatNullableCount(metrics.dau),
                    icon: Icons.today,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'WAU',
                    value: _formatNullableCount(metrics.wau),
                    icon: Icons.view_week,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'MAU',
                    value: _formatNullableCount(metrics.mau),
                    icon: Icons.calendar_view_month,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // SYSTEM TOTALS
            AppText(
              'SYSTEM TOTALS',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'Total Events',
                    value: '${metrics.totalEvents}',
                    icon: Icons.event_note_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'Total Logins',
                    value: _formatNullableCount(metrics.totalLogins),
                    icon: Icons.login_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'Feedback',
                    value: '${metrics.totalFeedback}',
                    icon: Icons.feedback_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // QUICK NAVIGATION TILES
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
              leading: Icon(
                Icons.manage_accounts_outlined,
                color: colorScheme.primary,
              ),
              title: const AppText('Manage Users & Streaks'),
              subtitle: const AppText('View unique users, logins & logout history'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => Navigator.pushNamed(context, '/admin/users'),
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
              leading: Icon(
                Icons.mark_chat_unread_outlined,
                color: colorScheme.primary,
              ),
              title: const AppText('Feedback Inbox'),
              subtitle: const AppText('Triage ratings, bug reports, and admin notes'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => Navigator.pushNamed(context, '/admin/feedback'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: AppText(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(icon, size: 18, color: colorScheme.primary),
              ],
            ),
            const SizedBox(height: 10),
            AppText(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
