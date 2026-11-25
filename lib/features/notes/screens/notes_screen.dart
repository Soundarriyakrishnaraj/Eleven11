import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../badges/badge_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  static const String _storageKey = 'eleven11_user_notes';
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    final parsed = <Map<String, dynamic>>[];
    for (final item in raw) {
      try {
        parsed.add(Map<String, dynamic>.from(jsonDecode(item) as Map));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _notes = parsed;
      _loading = false;
    });
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _notes.map((n) => jsonEncode(n)).toList(),
    );
  }

  Future<void> _openEditor({Map<String, dynamic>? existing, int? index}) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _NoteEditorScreen(initialNote: existing),
      ),
    );
    if (result == null) return;

    setState(() {
      if (index != null) {
        _notes[index] = result;
      } else {
        _notes.insert(0, result);
      }
    });
    await _saveNotes();
    if (index == null) {
      await BadgeService.recordNoteCreated(
        result['id'].toString(),
        DateTime.now(),
      );
    }
  }

  Future<void> _deleteNote(int index) async {
    setState(() => _notes.removeAt(index));
    await _saveNotes();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'NOTES',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        foregroundColor: theme.colorScheme.onPrimary,
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : _notes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.note_alt_outlined,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No notes yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap + to write a formatted note.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 88),
                  itemCount: _notes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    final title = (note['title'] ?? '').toString().trim();
                    final body = (note['body'] ?? '').toString();
                    final updatedAt = note['updatedAt'] != null
                        ? DateFormat('MMM d, HH:mm')
                            .format(DateTime.parse(note['updatedAt'].toString()).toLocal())
                        : '';

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openEditor(existing: note, index: index),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.colorScheme.outline),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title.isEmpty ? 'Untitled Note' : title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    if (body.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        body,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    if (updatedAt.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        updatedAt,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                onPressed: () => _deleteNote(index),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _NoteEditorScreen extends StatefulWidget {
  const _NoteEditorScreen({this.initialNote});

  final Map<String, dynamic>? initialNote;

  @override
  State<_NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<_NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  String _align = 'left'; // 'left' | 'center' | 'right'
  double _fontSize = 14.0;

  @override
  void initState() {
    super.initState();
    final n = widget.initialNote;
    _titleController = TextEditingController(text: n?['title']?.toString() ?? '');
    _bodyController = TextEditingController(text: n?['body']?.toString() ?? '');
    _isBold = n?['bold'] == true;
    _isItalic = n?['italic'] == true;
    _isUnderline = n?['underline'] == true;
    _align = n?['align']?.toString() ?? 'left';
    _fontSize = (n?['fontSize'] as num?)?.toDouble() ?? 14.0;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  TextAlign get _textAlign {
    switch (_align) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  void _saveAndClose() {
    final title = _titleController.text.trim();
    final body = _bodyController.text;
    if (title.isEmpty && body.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop({
      'id': widget.initialNote?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'body': body,
      'bold': _isBold,
      'italic': _isItalic,
      'underline': _isUnderline,
      'align': _align,
      'fontSize': _fontSize,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'EDIT NOTE',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveAndClose,
            child: Text(
              'SAVE',
              style: TextStyle(color: accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Formatting Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _formatBtn(
                    icon: Icons.format_bold,
                    active: _isBold,
                    accent: accent,
                    onTap: () => setState(() => _isBold = !_isBold),
                  ),
                  _formatBtn(
                    icon: Icons.format_italic,
                    active: _isItalic,
                    accent: accent,
                    onTap: () => setState(() => _isItalic = !_isItalic),
                  ),
                  _formatBtn(
                    icon: Icons.format_underline,
                    active: _isUnderline,
                    accent: accent,
                    onTap: () => setState(() => _isUnderline = !_isUnderline),
                  ),
                  const SizedBox(width: 8),
                  _formatBtn(
                    icon: Icons.format_align_left,
                    active: _align == 'left',
                    accent: accent,
                    onTap: () => setState(() => _align = 'left'),
                  ),
                  _formatBtn(
                    icon: Icons.format_align_center,
                    active: _align == 'center',
                    accent: accent,
                    onTap: () => setState(() => _align = 'center'),
                  ),
                  _formatBtn(
                    icon: Icons.format_align_right,
                    active: _align == 'right',
                    accent: accent,
                    onTap: () => setState(() => _align = 'right'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _fontSize = _fontSize == 14.0
                            ? 17.0
                            : (_fontSize == 17.0 ? 12.0 : 14.0);
                      });
                    },
                    child: Text(
                      '${_fontSize.toInt()}pt',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    textAlign: _textAlign,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Note title...',
                      border: InputBorder.none,
                    ),
                  ),
                  const Divider(height: 12),
                  Expanded(
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      expands: true,
                      textAlign: _textAlign,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontSize: _fontSize,
                        fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
                        fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
                        decoration: _isUnderline
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        color: theme.colorScheme.onSurface,
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Start writing...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatBtn({
    required IconData icon,
    required bool active,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return IconButton(
      icon: Icon(
        icon,
        size: 20,
        color: active ? accent : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: onTap,
    );
  }
}
