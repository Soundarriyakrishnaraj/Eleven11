import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// General inline checklist on the Home Dashboard (Add a task + checklist).
class HomeQuickTodo extends StatefulWidget {
  const HomeQuickTodo({super.key});

  @override
  State<HomeQuickTodo> createState() => _HomeQuickTodoState();
}

class _HomeQuickTodoState extends State<HomeQuickTodo> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _items = [];

  String get _storageKey {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    return 'home_quick_todos_$uid';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const [];
    final parsed = <Map<String, dynamic>>[];
    for (final s in raw) {
      try {
        parsed.add(Map<String, dynamic>.from(jsonDecode(s) as Map));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _items = parsed);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _items.map((e) => jsonEncode(e)).toList(),
    );
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() {
      _items.insert(0, {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': text,
        'done': false,
      });
    });
    await _save();
  }

  Future<void> _toggle(int index) async {
    setState(() {
      _items[index]['done'] = !(_items[index]['done'] == true);
    });
    await _save();
  }

  Future<void> _delete(int index) async {
    setState(() => _items.removeAt(index));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ADD A TASK',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: 'What needs to be done...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  filled: true,
                  fillColor: scheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: scheme.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: scheme.outline),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: _add,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add, color: scheme.onPrimary, size: 22),
              ),
            ),
          ],
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'YOUR CHECKLIST',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _items.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outline),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _items[i]['done'] == true,
                    activeColor: accent,
                    onChanged: (_) => _toggle(i),
                  ),
                  Expanded(
                    child: Text(
                      (_items[i]['title'] ?? '').toString(),
                      style: TextStyle(
                        fontSize: 13.5,
                        color: _items[i]['done'] == true
                            ? scheme.onSurface.withValues(alpha: 0.5)
                            : scheme.onSurface,
                        decoration: _items[i]['done'] == true
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: scheme.error,
                      size: 20,
                    ),
                    onPressed: () => _delete(i),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
