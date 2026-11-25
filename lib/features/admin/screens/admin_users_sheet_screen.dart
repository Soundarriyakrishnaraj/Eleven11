import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_text.dart';
import '../services/admin_service.dart';

const MethodChannel _fileChannel = MethodChannel('com.eleven11/audio_picker');

const List<String> kUserSheetHeaders = [
  'Username',
  'Email',
  'Date of Birth',
  'Timezone',
  'Registered',
  'User ID',
];

String _fmtDate(Object? v, String pattern) {
  final d = DateTime.tryParse(v?.toString() ?? '');
  return d == null ? '—' : DateFormat(pattern).format(d.toLocal());
}

/// One row of display values, in the same order as [kUserSheetHeaders].
List<String> userSheetRow(Map<String, dynamic> u) => [
      (u['username'] ?? '—').toString(),
      (u['email'] ?? '—').toString(),
      u['date_of_birth'] == null
          ? '—'
          : DateFormat('d MMM yyyy')
              .format(DateTime.parse(u['date_of_birth'].toString())),
      (u['tz'] ?? 'UTC').toString(),
      _fmtDate(u['created_at'], 'd MMM yyyy, HH:mm'),
      (u['id'] ?? '').toString(),
    ];

/// Spreadsheet-style view of all users with an Excel (.xlsx) download.
class AdminUsersSheetScreen extends StatefulWidget {
  const AdminUsersSheetScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  State<AdminUsersSheetScreen> createState() => _AdminUsersSheetScreenState();
}

class _AdminUsersSheetScreenState extends State<AdminUsersSheetScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await widget.adminService.fetchAllUsers();
      if (!mounted) return;
      setState(() {
        _users = all;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    setState(() => _exporting = true);
    try {
      final book = xl.Excel.createExcel();
      final sheet = book['Users'];
      book.delete('Sheet1');
      sheet.appendRow([for (final h in kUserSheetHeaders) xl.TextCellValue(h)]);
      for (final u in _users) {
        sheet.appendRow([for (final v in userSheetRow(u)) xl.TextCellValue(v)]);
      }
      final bytes = book.encode();
      if (bytes == null) throw Exception('Could not build the spreadsheet.');

      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final name = 'eleven11_users_$stamp.xlsx';
      final location = await _fileChannel.invokeMethod<String>(
        'saveToDownloads',
        {
          'name': name,
          'bytes': Uint8List.fromList(bytes),
          'mime':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${location ?? 'Downloads'}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const AppText('USERS SHEET'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Download sheet (.xlsx)',
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            onPressed: (_loading || _exporting || _users.isEmpty)
                ? null
                : _download,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: TextStyle(color: scheme.error)),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const AppText('Retry')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppText('${_users.length} users',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          FilledButton.icon(
                            onPressed: (_exporting || _users.isEmpty)
                                ? null
                                : _download,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const AppText('Download sheet'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 20,
                            headingRowColor: WidgetStateProperty.all(
                              scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                            ),
                            columns: [
                              for (final h in kUserSheetHeaders)
                                DataColumn(
                                  label: AppText(h,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ),
                            ],
                            rows: [
                              for (final u in _users)
                                DataRow(cells: [
                                  for (final v in userSheetRow(u))
                                    DataCell(Text(v,
                                        style:
                                            const TextStyle(fontSize: 12))),
                                ]),
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
