import 'package:material_ui/material_ui.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/eink_palette.dart';
import '../../../core/theme/eink_theme_extension.dart';

/// Ruled paper painter to create real electronic paper notebook lines
class RuledPaperPainter extends CustomPainter {
  RuledPaperPainter({
    required this.lineColor,
    this.lineSpacing = 28.0,
    this.topMargin = 40.0,
  });

  final Color lineColor;
  final double lineSpacing;
  final double topMargin;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    double y = topMargin;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += lineSpacing;
    }
  }

  @override
  bool shouldRepaint(covariant RuledPaperPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.lineSpacing != lineSpacing ||
        oldDelegate.topMargin != topMargin;
  }
}

/// E-Ink Notes reader and editor surface widget that respects paper style,
/// soft borders, and E-Ink highlighter colors.
class EInkNoteCard extends StatelessWidget {
  const EInkNoteCard({
    super.key,
    required this.title,
    required this.content,
    this.date,
    this.highlightColor,
    this.onTap,
  });

  final String title;
  final String content;
  final String? date;
  final Color? highlightColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eink = theme.extension<Eleven11EInkExtension>();
    final isEInk = eink?.isEInkMode ?? false;

    final bgColor = isEInk ? eink!.paperBackground : theme.colorScheme.surface;
    final borderColor = isEInk ? eink!.subtleBorder : theme.colorScheme.outline;
    final textColor = isEInk ? eink!.inkColor : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isEInk ? 0.02 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (highlightColor != null) ...[
              Container(
                height: 4,
                width: 36,
                decoration: BoxDecoration(
                  color: highlightColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                if (date != null)
                  Text(
                    date!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isEInk ? EInkPalette.slateGrey : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: textColor.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone Notes E-Ink Reading & Editor Screen
class EInkNoteEditorScreen extends StatefulWidget {
  const EInkNoteEditorScreen({
    super.key,
    this.initialTitle = '',
    this.initialContent = '',
  });

  final String initialTitle;
  final String initialContent;

  @override
  State<EInkNoteEditorScreen> createState() => _EInkNoteEditorScreenState();
}

class _EInkNoteEditorScreenState extends State<EInkNoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  Color? _selectedHighlighter;
  late Color _paperColor;
  late bool _showRuled;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _contentController = TextEditingController(text: widget.initialContent);
    final notifier = ThemeNotifier.instance;
    _paperColor = notifier.einkPaper;
    _showRuled = notifier.einkRuledLines;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eink = theme.extension<Eleven11EInkExtension>();
    final isEInk = eink?.isEInkMode ?? false;

    final highlighters = [
      {'name': 'Yellow', 'color': eink?.highlightYellow ?? const Color(0x66E8D79B)},
      {'name': 'Mint', 'color': eink?.highlightGreen ?? const Color(0x6697C1A9)},
      {'name': 'Peach', 'color': eink?.highlightOrange ?? const Color(0x66E8AA7B)},
      {'name': 'Pink', 'color': eink?.highlightPink ?? const Color(0x66DEABB7)},
      {'name': 'Blue', 'color': eink?.highlightBlue ?? const Color(0x669FB6CD)},
    ];

    return Scaffold(
      backgroundColor: _paperColor,
      appBar: AppBar(
        backgroundColor: _paperColor,
        elevation: 0,
        title: Text(
          'NOTE',
          style: TextStyle(
            color: isEInk ? EInkPalette.charcoal : theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 15,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showRuled ? Icons.grid_off_rounded : Icons.grid_on_rounded,
              color: isEInk ? EInkPalette.charcoal : theme.colorScheme.onSurface,
            ),
            tooltip: _showRuled ? 'Hide ruled lines' : 'Show ruled lines',
            onPressed: () {
              setState(() => _showRuled = !_showRuled);
            },
          ),
          IconButton(
            icon: Icon(
              Icons.check_rounded,
              color: isEInk ? EInkPalette.charcoal : theme.colorScheme.onSurface,
            ),
            tooltip: 'Save Note',
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_showRuled)
            Positioned.fill(
              child: CustomPaint(
                painter: RuledPaperPainter(
                  lineColor: isEInk
                      ? eink?.ruledLineColor ?? const Color(0x30868E96)
                      : theme.colorScheme.outline.withValues(alpha: 0.35),
                  lineSpacing: 30.0,
                  topMargin: 80.0,
                ),
              ),
            ),
          Column(
            children: [
              // Highlighter Toolbar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isEInk ? eink!.subtleBorder : theme.colorScheme.outline,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Highlighter:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: EInkPalette.slateGrey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    ...highlighters.map((h) {
                      final c = h['color'] as Color;
                      final isSelected = _selectedHighlighter == c;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedHighlighter = isSelected ? null : c;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? EInkPalette.charcoal
                                    : Colors.black12,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 14, color: EInkPalette.charcoal)
                                : null,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              // Title Field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: TextField(
                  controller: _titleController,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isEInk ? EInkPalette.charcoal : theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Note Title...',
                    hintStyle: TextStyle(
                      color: isEInk ? EInkPalette.silverGrey : theme.colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),

              // Content Field
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _contentController,
                    maxLines: null,
                    expands: true,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: isEInk ? EInkPalette.charcoal : theme.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Start writing your note on e-paper...',
                      hintStyle: TextStyle(
                        color: isEInk ? EInkPalette.silverGrey : theme.colorScheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
