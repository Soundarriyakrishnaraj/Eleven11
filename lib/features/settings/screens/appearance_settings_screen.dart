import 'package:material_ui/material_ui.dart';

import '../../../core/providers/theme_provider.dart';
import '../widgets/settings_tile.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  late ThemeMode _currentMode;
  late Color _selectedAccent;
  late TextEditingController _hexController;

  late int _r;
  late int _g;
  late int _b;

  static const List<Map<String, dynamic>> _presets = [
    {'name': 'Eleven11 Orange', 'color': kSignatureOrange},
    {'name': 'Gold Amber', 'color': kSignatureGold},
    {'name': 'Sunset Flame', 'color': Color(0xFFFF5722)},
    {'name': 'Crimson Red', 'color': Color(0xFFE53935)},
    {'name': 'Emerald Green', 'color': Color(0xFF4CAF50)},
    {'name': 'Neon Cyan', 'color': Color(0xFF00E5FF)},
    {'name': 'Electric Blue', 'color': Color(0xFF2979FF)},
    {'name': 'Amethyst Purple', 'color': Color(0xFF9C27B0)},
    {'name': 'Hot Pink', 'color': Color(0xFFFF4081)},
  ];

  @override
  void initState() {
    super.initState();
    _currentMode = ThemeNotifier.instance.mode;
    _selectedAccent = ThemeNotifier.instance.accent;

    _r = (_selectedAccent.r * 255).round().clamp(0, 255);
    _g = (_selectedAccent.g * 255).round().clamp(0, 255);
    _b = (_selectedAccent.b * 255).round().clamp(0, 255);

    _hexController = TextEditingController(text: _colorToHex(_selectedAccent));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final g = (color.g * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final b = (color.b * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }

  void _onRgbChanged(int r, int g, int b) {
    setState(() {
      _r = r;
      _g = g;
      _b = b;
      _selectedAccent = Color.fromARGB(255, r, g, b);
      _hexController.text = _colorToHex(_selectedAccent);
    });
  }

  void _onHexChanged(String hex) {
    String cleanHex = hex.replaceAll('#', '').trim();
    if (cleanHex.length == 6) {
      final intVal = int.tryParse(cleanHex, radix: 16);
      if (intVal != null) {
        final color = Color(0xFF000000 | intVal);
        setState(() {
          _selectedAccent = color;
          _r = (color.r * 255).round().clamp(0, 255);
          _g = (color.g * 255).round().clamp(0, 255);
          _b = (color.b * 255).round().clamp(0, 255);
        });
      }
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _currentMode = mode);
    await ThemeNotifier.instance.setMode(mode);
  }

  Future<void> _applyAccentColor(Color color) async {
    setState(() {
      _selectedAccent = color;
      _r = (color.r * 255).round().clamp(0, 255);
      _g = (color.g * 255).round().clamp(0, 255);
      _b = (color.b * 255).round().clamp(0, 255);
      _hexController.text = _colorToHex(color);
    });
    await ThemeNotifier.instance.setAccentColor(color);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Accent colour updated to ${_colorToHex(color)}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _resetToDefault() async {
    await ThemeNotifier.instance.resetAccentColor();
    await ThemeNotifier.instance.setMode(ThemeMode.dark);
    setState(() {
      _currentMode = ThemeMode.dark;
      _selectedAccent = kDefaultAccent;
      _r = (_selectedAccent.r * 255).round().clamp(0, 255);
      _g = (_selectedAccent.g * 255).round().clamp(0, 255);
      _b = (_selectedAccent.b * 255).round().clamp(0, 255);
      _hexController.text = _colorToHex(_selectedAccent);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Appearance reset to Eleven11 defaults.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surface;
    final borderColor = theme.colorScheme.outline;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'APPEARANCE',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // PREVIEW CARD
          _buildLivePreviewCard(cardColor, borderColor),
          const SizedBox(height: 24),

          // THEME MODE
          const SettingsSectionHeader('THEME MODE'),
          const SizedBox(height: 6),
          _buildThemeModeSelector(cardColor, borderColor),
          const SizedBox(height: 24),

          // PRESET ACCENT COLORS
          const SettingsSectionHeader('ACCENT PRESETS'),
          const SizedBox(height: 8),
          _buildPresetsGrid(cardColor, borderColor),
          const SizedBox(height: 24),

          // CUSTOM COLOR PICKER
          const SettingsSectionHeader('CUSTOM ACCENT COLOR'),
          const SizedBox(height: 8),
          _buildCustomColorPicker(cardColor, borderColor),
          const SizedBox(height: 20),

          // APPLY BUTTON
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _selectedAccent,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _applyAccentColor(_selectedAccent),
              icon: const Icon(Icons.check, size: 20),
              label: const Text(
                'APPLY ACCENT COLOR',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // RESET BUTTON
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _resetToDefault,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text(
                'RESET TO DEFAULT',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLivePreviewCard(Color cardColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _selectedAccent.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _selectedAccent.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _selectedAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.palette_rounded,
                  color: _selectedAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Accent Preview',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _colorToHex(_selectedAccent),
                      style: TextStyle(
                        color: _selectedAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _selectedAccent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: 0.75,
              minHeight: 8,
              backgroundColor: _selectedAccent.withValues(alpha: 0.2),
              color: _selectedAccent,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _selectedAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Active Streak: 11',
                  style: TextStyle(
                    color: _selectedAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.star_rounded, color: _selectedAccent, size: 18),
              const SizedBox(width: 4),
              Text(
                '1,111 PTS',
                style: TextStyle(
                  color: _selectedAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeModeSelector(Color cardColor, Color borderColor) {
    return Material(
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Column(
        children: [
          _themeRadioTile(
            title: 'Dark Theme',
            subtitle: 'Eleven11 matte black aesthetic',
            icon: Icons.dark_mode_outlined,
            mode: ThemeMode.dark,
          ),
          Divider(height: 1, color: borderColor),
          _themeRadioTile(
            title: 'Light Theme',
            subtitle: 'Clean ivory high-contrast surfaces',
            icon: Icons.light_mode_outlined,
            mode: ThemeMode.light,
          ),
          Divider(height: 1, color: borderColor),
          _themeRadioTile(
            title: 'System Default',
            subtitle: 'Automatically follow device system theme',
            icon: Icons.brightness_auto_outlined,
            mode: ThemeMode.system,
          ),
        ],
      ),
    );
  }

  Widget _themeRadioTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeMode mode,
  }) {
    final selected = _currentMode == mode;
    final primaryAccent = Theme.of(context).colorScheme.primary;

    return ListTile(
      leading: Icon(
        icon,
        color: selected
            ? primaryAccent
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: primaryAccent, size: 22)
          : Icon(
              Icons.circle_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
      onTap: () => _setThemeMode(mode),
    );
  }

  Widget _buildPresetsGrid(Color cardColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _presets.map((preset) {
          final theme = Theme.of(context);
          final color = preset['color'] as Color;
          final isSelected =
              (_selectedAccent.toARGB32() & 0x00FFFFFF) ==
              (color.toARGB32() & 0x00FFFFFF);

          return Tooltip(
            message: preset['name'] as String,
            child: InkWell(
              onTap: () {
                _onRgbChanged(
                  (color.r * 255).round().clamp(0, 255),
                  (color.g * 255).round().clamp(0, 255),
                  (color.b * 255).round().clamp(0, 255),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(
                      alpha: isSelected ? 1 : 0.26,
                    ),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        color:
                            ThemeData.estimateBrightnessForColor(color) ==
                                Brightness.dark
                            ? const Color(0xFFF5F1E8)
                            : const Color(0xFF211D18),
                        size: 26,
                      )
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCustomColorPicker(Color cardColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEX INPUT
          Row(
            children: [
              const Text(
                'HEX CODE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _hexController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    prefixText: '# ',
                    prefixStyle: TextStyle(
                      color: _selectedAccent,
                      fontWeight: FontWeight.bold,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _selectedAccent, width: 2),
                    ),
                  ),
                  onChanged: _onHexChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // RGB SLIDERS
          _buildRgbSlider('RED (R)', _r, Colors.redAccent, (val) {
            _onRgbChanged(val.round(), _g, _b);
          }, key: const ValueKey('red-slider')),
          _buildRgbSlider('GREEN (G)', _g, Colors.greenAccent, (val) {
            _onRgbChanged(_r, val.round(), _b);
          }, key: const ValueKey('green-slider')),
          _buildRgbSlider('BLUE (B)', _b, Colors.lightBlueAccent, (val) {
            _onRgbChanged(_r, _g, val.round());
          }, key: const ValueKey('blue-slider')),
        ],
      ),
    );
  }

  Widget _buildRgbSlider(
    String label,
    int value,
    Color activeColor,
    ValueChanged<double> onChanged, {
    required Key key,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: activeColor,
                thumbColor: activeColor,
                overlayColor: activeColor.withValues(alpha: 0.2),
              ),
              child: Slider(
                key: key,
                value: value.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 35,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
