import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'badge_engine.dart';
import 'badge_service.dart';

const Map<BadgeId, IconData> _icons = {
  BadgeId.firstGoal: Icons.flag_rounded,
  BadgeId.goalSetter: Icons.track_changes,
  BadgeId.goalCrusher: Icons.emoji_events,
  BadgeId.taskMaster: Icons.checklist_rounded,
  BadgeId.earlyBird: Icons.wb_sunny_rounded,
  BadgeId.nightOwl: Icons.nights_stay_rounded,
  BadgeId.noteTaker: Icons.edit_note_rounded,
  BadgeId.planner: Icons.event_available,
};

/// Activity badges earned from goals, tasks, notes and calendar events.
/// (Separate from the 6 streak milestone badges on the Streak screen.)
class BadgeShelf extends StatefulWidget {
  const BadgeShelf({super.key, required this.cardColor, required this.accent});

  final Color cardColor;
  final Color accent;

  @override
  State<BadgeShelf> createState() => _BadgeShelfState();
}

class _BadgeShelfState extends State<BadgeShelf> {
  final BadgeService _service = BadgeService();
  List<BadgeResult>? _results;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    BadgeService.changes.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    BadgeService.changes.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await _service.load();
      if (!mounted) return;
      setState(() {
        _results = r;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = _results == null);
    }
  }

  void _showDetails(BadgeResult r) {
    final scheme = Theme.of(context).colorScheme;
    final d = r.definition;
    final text = r.earned
        ? 'Earned on ${DateFormat('d MMM yyyy').format(r.earnedAt!)}'
        : '${d.requirement}\nProgress: ${r.shownProgress}/${d.target}';
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icons[d.id],
                  size: 40,
                  color: r.earned
                      ? widget.accent
                      : scheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(height: 10),
              Text(d.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _results;
    final earnedCount = results?.where((r) => r.earned).length ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Badges',
                    style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              if (results != null)
                Text('$earnedCount/${results.length}',
                    style: TextStyle(color: widget.accent, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          if (results == null)
            Text(_failed ? 'Badges unavailable offline' : 'Loading…',
                style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11))
          else
            LayoutBuilder(builder: (context, c) {
              // 4 columns on normal phones, 3 on very narrow ones.
              final cols = c.maxWidth < 280 ? 3 : 4;
              const gap = 8.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: 12,
                children: [
                  for (final r in results)
                    SizedBox(
                      width: w,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showDetails(r),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.accent
                                    .withValues(alpha: r.earned ? 0.22 : 0.08),
                                border: r.earned
                                    ? Border.all(color: widget.accent)
                                    : null,
                              ),
                              child: Icon(
                                _icons[r.definition.id],
                                size: 22,
                                color: r.earned
                                    ? widget.accent
                                    : scheme.onSurface.withValues(alpha: 0.3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.definition.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurface
                                    .withValues(alpha: r.earned ? 0.95 : 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }
}
