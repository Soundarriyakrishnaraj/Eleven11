import 'package:material_ui/material_ui.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/eink_palette.dart';

class EInkColorSettingsScreen extends StatefulWidget {
  const EInkColorSettingsScreen({super.key});

  @override
  State<EInkColorSettingsScreen> createState() =>
      _EInkColorSettingsScreenState();
}

class _EInkColorSettingsScreenState extends State<EInkColorSettingsScreen> {
  String _selectedCategory = 'All';
  late Color _currentAccent;
  late Color _currentPaper;
  late bool _ruledLines;

  @override
  void initState() {
    super.initState();
    final notifier = ThemeNotifier.instance;
    _currentAccent = notifier.einkAccent;
    _currentPaper = notifier.einkPaper;
    _ruledLines = notifier.einkRuledLines;
  }

  List<EInkColorItem> get _filteredColors {
    if (_selectedCategory == 'All') {
      return EInkPalette.allColors;
    }
    return EInkPalette.allColors
        .where((c) => c.category == _selectedCategory)
        .toList();
  }

  Future<void> _selectAccent(Color color) async {
    setState(() => _currentAccent = color);
    await ThemeNotifier.instance.setEInkAccentColor(color);
  }

  Future<void> _selectPaper(Color color) async {
    setState(() => _currentPaper = color);
    await ThemeNotifier.instance.setEInkPaperColor(color);
  }

  Future<void> _toggleRuled(bool enabled) async {
    setState(() => _ruledLines = enabled);
    await ThemeNotifier.instance.setEInkRuledLines(enabled);
  }

  Future<void> _applyPreset(EInkPreset preset) async {
    setState(() {
      _currentAccent = preset.accentColor;
      _currentPaper = preset.paperColor;
    });
    await ThemeNotifier.instance.applyEInkPreset(preset);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied "${preset.name}" preset.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _resetToDefault() async {
    await ThemeNotifier.instance.resetEInkPalette();
    setState(() {
      _currentAccent = ThemeNotifier.instance.einkAccent;
      _currentPaper = ThemeNotifier.instance.einkPaper;
      _ruledLines = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reset to Full Color E-Ink defaults.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEInk = ThemeNotifier.instance.isEInkMode;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'E-INK COLOR THEME',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_outlined),
            tooltip: 'Reset Palette',
            onPressed: _resetToDefault,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // E-INK MODE ACTIVE SWITCH BANNER
          _buildEInkStatusBanner(theme, isEInk),
          const SizedBox(height: 20),

          // LIVE E-INK PREVIEW
          _buildLiveEInkPreview(theme),
          const SizedBox(height: 24),

          // CURATED PRESETS
          _buildSectionHeader('CURATED E-INK PRESETS'),
          const SizedBox(height: 10),
          _buildPresetsCarousel(theme),
          const SizedBox(height: 24),

          // PAPER BACKGROUND SELECTION
          _buildSectionHeader('PAPER BACKGROUND'),
          const SizedBox(height: 6),
          const Text(
            'Select the base electronic paper tone for reading and notes.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          _buildPaperToneSelector(theme),
          const SizedBox(height: 24),

          // RULED PAPER OPTION
          _buildRuledPaperToggle(theme),
          const SizedBox(height: 24),

          // FULL PALETTE ACCENT SELECTION
          _buildSectionHeader('E-INK ACCENT PALETTE'),
          const SizedBox(height: 6),
          const Text(
            'Choose an e-paper accent color for highlights, chips, and buttons.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),

          // CATEGORY CHIPS
          _buildCategoryChips(theme),
          const SizedBox(height: 14),

          // COLOR SWATCHES GRID
          _buildColorSwatchesGrid(theme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildEInkStatusBanner(ThemeData theme, bool isEInk) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _currentAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_stories_rounded,
              color: _currentAccent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'E-Ink Color Theme',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  isEInk
                      ? 'Active throughout Eleven11'
                      : 'Disabled (Tap switch to activate)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isEInk
                        ? _currentAccent
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isEInk,
            onChanged: (val) async {
              await ThemeNotifier.instance.setEInkMode(val);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveEInkPreview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _currentPaper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _currentAccent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'E-INK SIMULATION',
                  style: TextStyle(
                    color: EInkPalette.paperWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.bookmark_outline_rounded, color: _currentAccent, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Gentle Electronic Paper Reading',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: EInkPalette.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Calm, low-glare paper surface with muted color accents, dark charcoal typography and zero neon distraction.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: EInkPalette.charcoal,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _currentAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _currentAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.palette_outlined, size: 14, color: _currentAccent),
                    const SizedBox(width: 6),
                    Text(
                      'Accent: ${_colorHex(_currentAccent)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _currentAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Text(
                  'Paper: ${_colorHex(_currentPaper)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: EInkPalette.slateGrey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsCarousel(ThemeData theme) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EInkPresets.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final preset = EInkPresets.all[index];
          final isSelected = _currentAccent.toARGB32() == preset.accentColor.toARGB32() &&
              _currentPaper.toARGB32() == preset.paperColor.toARGB32();

          return InkWell(
            onTap: () => _applyPreset(preset),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: preset.paperColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? preset.accentColor : theme.colorScheme.outline,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: preset.accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Spacer(),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: preset.accentColor,
                        ),
                    ],
                  ),
                  Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: EInkPalette.charcoal,
                    ),
                  ),
                  Text(
                    preset.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: EInkPalette.slateGrey,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaperToneSelector(ThemeData theme) {
    final papers = [
      {'name': 'Paper White', 'color': EInkPalette.paperWhite},
      {'name': 'Ivory', 'color': EInkPalette.ivory},
      {'name': 'Warm White', 'color': EInkPalette.warmWhite},
      {'name': 'Cream', 'color': EInkPalette.cream},
      {'name': 'Antique White', 'color': EInkPalette.antiqueWhite},
      {'name': 'Light Grey', 'color': EInkPalette.lightGrey},
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: papers.map((p) {
        final color = p['color'] as Color;
        final name = p['name'] as String;
        final isSelected = _currentPaper.toARGB32() == color.toARGB32();

        return InkWell(
          onTap: () => _selectPaper(color),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _currentAccent : theme.colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(Icons.check, size: 14, color: _currentAccent),
                  const SizedBox(width: 6),
                ],
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: EInkPalette.charcoal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRuledPaperToggle(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.reorder_rounded, size: 22),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ruled Paper Appearance',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                Text(
                  'Display subtle notebook line guides in notes & journals',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: _ruledLines,
            onChanged: _toggleRuled,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(ThemeData theme) {
    final categories = ['All', ...EInkPalette.categories];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat;

          return ChoiceChip(
            label: Text(cat, style: const TextStyle(fontSize: 12)),
            selected: isSelected,
            selectedColor: _currentAccent.withValues(alpha: 0.2),
            onSelected: (selected) {
              if (selected) {
                setState(() => _selectedCategory = cat);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildColorSwatchesGrid(ThemeData theme) {
    final colors = _filteredColors;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: colors.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final item = colors[index];
        final isSelected = _currentAccent.toARGB32() == item.color.toARGB32();

        return InkWell(
          onTap: () => _selectAccent(item.color),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? item.color : theme.colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Swatch with light & dark tint bars
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: EInkPalette.paperWhite,
                            )
                          : null,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 4,
                          color: item.lightTint,
                        ),
                        Container(
                          width: 10,
                          height: 4,
                          color: item.darkTint,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      Text(
                        _colorHex(item.color),
                        style: TextStyle(
                          fontSize: 10,
                          color: item.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _colorHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}
