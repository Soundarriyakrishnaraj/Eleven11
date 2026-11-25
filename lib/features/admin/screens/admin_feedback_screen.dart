import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_text.dart';
import '../services/admin_service.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key, this.adminService});

  final AdminService? adminService;

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  late final AdminService _adminService;
  late final bool _ownsService;

  bool _isLoading = true;
  String? _errorMessage;
  bool _triageColumnsAvailable = true;
  List<Map<String, dynamic>> _feedbackList = [];
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _ownsService = widget.adminService == null;
    _adminService = widget.adminService ?? AdminService();
    _fetchFeedback();
  }

  @override
  void dispose() {
    if (_ownsService) {
      _adminService.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchFeedback() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _adminService.fetchFeedback(status: _filterStatus);
      if (!mounted) return;
      setState(() {
        _feedbackList = result.items;
        _triageColumnsAvailable = result.triageColumnsAvailable;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _updateFeedback(String id, String newStatus, String adminNote) async {
    try {
      await _adminService.updateFeedback(
        id: id,
        status: newStatus,
        adminNote: adminNote,
      );
      await _fetchFeedback();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback status updated successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showTriageDialog(Map<String, dynamic> item) {
    final noteController = TextEditingController(text: item['admin_note']?.toString() ?? '');
    String status = item['status']?.toString() ?? 'new';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const AppText('Triage Feedback'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      'Submitted By:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item['username'] ?? item['full_name'] ?? 'User'} (${item['user_id'] ?? 'N/A'})',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    AppText(
                      'User Message:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['message']?.toString() ?? '',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    const AppText('Update Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'new', child: Text('New')),
                        DropdownMenuItem(value: 'reviewed', child: Text('Reviewed')),
                        DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                        DropdownMenuItem(value: 'dismissed', child: Text('Dismissed')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => status = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    const AppText('Internal Admin Note:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter confidential admin notes...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const AppText('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _updateFeedback(item['id'].toString(), status, noteController.text);
                  },
                  child: const AppText('Save Changes'),
                ),
              ],
            );
          },
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
        title: const AppText('FEEDBACK INBOX'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchFeedback,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_triageColumnsAvailable)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const AppText(
                'Triage status & admin note columns require Migration 016 approval. Baseline feedback messages are shown below.',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: ['all', 'new', 'reviewed', 'resolved', 'dismissed'].map((s) {
                final label = s[0].toUpperCase() + s.substring(1);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: label,
                    isSelected: _filterStatus == s,
                    onSelected: () {
                      setState(() => _filterStatus = s);
                      _fetchFeedback();
                    },
                  ),
                );
              }).toList(),
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
                              Text(_errorMessage!, style: TextStyle(color: colorScheme.error)),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _fetchFeedback,
                                child: const AppText('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _feedbackList.isEmpty
                        ? const Center(child: AppText('No feedback items found.'))
                        : RefreshIndicator(
                            onRefresh: _fetchFeedback,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  ),
                                  columns: const [
                                    DataColumn(label: AppText('STATUS', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: AppText('USER', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: AppText('RATING', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: AppText('MESSAGE', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: AppText('CATEGORY', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: AppText('DATE', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: AppText('ACTION', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: _feedbackList.map((item) {
                                    final rating = (item['rating'] as num?)?.toInt() ?? 0;
                                    final status = (item['status'] ?? 'new').toString();
                                    final category = (item['category'] ?? 'general').toString();
                                    final message = (item['message'] ?? '').toString();
                                    final userId = (item['user_id'] ?? '').toString();
                                    final submitter = (item['username'] ??
                                            item['full_name'] ??
                                            (userId.length > 8 ? '${userId.substring(0, 8)}…' : userId))
                                        .toString();
                                    final date = item['created_at'] != null
                                        ? DateFormat('MMM d, HH:mm').format(DateTime.parse(item['created_at']).toLocal())
                                        : '—';

                                    Color statusColor;
                                    switch (status) {
                                      case 'resolved':
                                        statusColor = Colors.green;
                                        break;
                                      case 'reviewed':
                                        statusColor = Colors.blue;
                                        break;
                                      case 'dismissed':
                                        statusColor = Colors.grey;
                                        break;
                                      default:
                                        statusColor = Colors.orange;
                                    }

                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                                            ),
                                            child: Text(
                                              status.toUpperCase(),
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(submitter, style: const TextStyle(fontWeight: FontWeight.w600))),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: List.generate(5, (idx) {
                                              return Icon(
                                                idx < rating ? Icons.star : Icons.star_border,
                                                size: 14,
                                                color: Colors.amber,
                                              );
                                            }),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 220,
                                            child: Text(
                                              message,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(category)),
                                        DataCell(Text(date, style: const TextStyle(fontSize: 11))),
                                        DataCell(
                                          IconButton(
                                            icon: const Icon(Icons.edit_note_rounded, size: 20),
                                            tooltip: _triageColumnsAvailable
                                                ? 'Triage Item'
                                                : 'Requires Migration 016',
                                            onPressed: _triageColumnsAvailable
                                                ? () => _showTriageDialog(item)
                                                : () {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Triage requires Migration 016 to be applied in Supabase.',
                                                        ),
                                                      ),
                                                    );
                                                  },
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: colorScheme.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
