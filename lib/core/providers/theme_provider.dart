import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/eink_palette.dart';
import '../theme/eink_theme_extension.dart';

const Color kBrandDarkBackground = Color(0xFF0A090E);
const Color kSignatureGold = Color(0xFFE4BE69);
const Color kSignatureOrange = Color(0xFFF28C00);
const Color kDefaultAccent = kSignatureOrange;
const Color kDarkBackground = kBrandDarkBackground;
const Color kDarkSurface = Color(0xFF222222);
const Color kLightBackground = Color(0xFFF7F2E8);
const Color kLightSurface = Color(0xFFFFFCF5);

/// Font style option: Normal (system default) or Custom TTF (MyHandwriting with uppercase mode)
enum FontStyleOption {
  normal,
  customTTF,
}

/// Supported App Themes including E-Ink Color
enum AppThemeMode {
  dark,
  light,
  system,
  eink,
}

@immutable
class Eleven11AccentPalette extends ThemeExtension<Eleven11AccentPalette> {
  const Eleven11AccentPalette({
    required this.accentPrimary,
    required this.accentDark,
    required this.accentLight,
    required this.accentSoft,
    required this.accentBorder,
    required this.accentPressed,
  });

  final Color accentPrimary;
  final Color accentDark;
  final Color accentLight;
  final Color accentSoft;
  final Color accentBorder;
  final Color accentPressed;

  factory Eleven11AccentPalette.fromColor(Color base, Color surface) {
    return Eleven11AccentPalette(
      accentPrimary: base,
      accentDark: _blend(base, kBrandDarkBackground, 0.26),
      accentLight: _blend(base, const Color(0xFFFFFFFF), 0.24),
      accentSoft: _blend(surface, base, 0.12),
      accentBorder: _blend(surface, base, 0.52),
      accentPressed: _blend(base, kBrandDarkBackground, 0.18),
    );
  }

  static Color _blend(Color from, Color to, double amount) {
    int channel(double start, double end) =>
        (start * 255 + (end * 255 - start * 255) * amount).round().clamp(
          0,
          255,
        );

    return Color.fromARGB(
      255,
      channel(from.r, to.r),
      channel(from.g, to.g),
      channel(from.b, to.b),
    );
  }

  @override
  Eleven11AccentPalette copyWith({
    Color? accentPrimary,
    Color? accentDark,
    Color? accentLight,
    Color? accentSoft,
    Color? accentBorder,
    Color? accentPressed,
  }) {
    return Eleven11AccentPalette(
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentDark: accentDark ?? this.accentDark,
      accentLight: accentLight ?? this.accentLight,
      accentSoft: accentSoft ?? this.accentSoft,
      accentBorder: accentBorder ?? this.accentBorder,
      accentPressed: accentPressed ?? this.accentPressed,
    );
  }

  @override
  Eleven11AccentPalette lerp(
    covariant ThemeExtension<Eleven11AccentPalette>? other,
    double t,
  ) {
    if (other is! Eleven11AccentPalette) return this;

    return Eleven11AccentPalette(
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentDark: Color.lerp(accentDark, other.accentDark, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
    );
  }
}

class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier();

  static final ThemeNotifier instance = ThemeNotifier();

  static const String _modeKey = 'settings_theme_mode';
  static const String _accentKey = 'settings_accent_color';
  static const String _isEInkKey = 'settings_is_eink_mode';
  static const String _einkPresetKey = 'settings_eink_preset';
  static const String _einkAccentKey = 'settings_eink_accent_color';
  static const String _einkPaperKey = 'settings_eink_paper_color';
  static const String _einkRuledKey = 'settings_eink_ruled_lines';
  static const String _fontOptionKey = 'settings_font_family_option';

  ThemeMode _mode = ThemeMode.system;
  Color _accent = kDefaultAccent;

  // E-Ink properties
  bool _isEInkMode = false;
  EInkPresetPalette _einkPreset = EInkPresetPalette.classicKaleido;
  Color _einkAccent = EInkPalette.classicKaleido.accent1;
  Color _einkPaper = EInkPalette.classicKaleido.background;
  bool _einkRuledLines = false;

  // Font Style Option
  FontStyleOption _fontOption = FontStyleOption.normal;

  ThemeMode get mode => _mode;
  Color get accent => _accent;
  bool get isEInkMode => _isEInkMode;
  EInkPresetPalette get einkPreset => _einkPreset;
  Color get einkAccent => _einkAccent;
  Color get einkPaper => _einkPaper;
  bool get einkRuledLines => _einkRuledLines;
  FontStyleOption get fontOption => _fontOption;
  bool get isUppercaseMode => _fontOption == FontStyleOption.customTTF;
  String? get fontFamily => _fontOption == FontStyleOption.customTTF ? 'MyHandwriting' : null;

  AppThemeMode get appThemeMode {
    if (_isEInkMode) return AppThemeMode.eink;
    switch (_mode) {
      case ThemeMode.dark:
        return AppThemeMode.dark;
      case ThemeMode.light:
        return AppThemeMode.light;
      case ThemeMode.system:
        return AppThemeMode.system;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Font style option
    final fontIndex = prefs.getInt(_fontOptionKey);
    if (fontIndex != null && fontIndex >= 0 && fontIndex < FontStyleOption.values.length) {
      _fontOption = FontStyleOption.values[fontIndex];
    } else {
      _fontOption = FontStyleOption.normal;
    }

    // E-Ink mode check
    _isEInkMode = prefs.getBool(_isEInkKey) ?? false;

    // E-Ink preset
    final presetIndex = prefs.getInt(_einkPresetKey);
    if (presetIndex != null && presetIndex >= 0 && presetIndex < EInkPresetPalette.values.length) {
      _einkPreset = EInkPresetPalette.values[presetIndex];
    } else {
      _einkPreset = EInkPresetPalette.classicKaleido;
    }

    final presetConfig = EInkPalette.getConfig(_einkPreset);

    // E-Ink accent
    final savedEInkAccent = prefs.getInt(_einkAccentKey);
    if (savedEInkAccent != null) {
      _einkAccent = Color(savedEInkAccent);
    } else {
      _einkAccent = presetConfig.accent1;
    }

    // E-Ink paper
    final savedEInkPaper = prefs.getInt(_einkPaperKey);
    if (savedEInkPaper != null) {
      _einkPaper = Color(savedEInkPaper);
    } else {
      _einkPaper = presetConfig.background;
    }

    // E-Ink ruled lines
    _einkRuledLines = prefs.getBool(_einkRuledKey) ?? false;

    // Normal ThemeMode
    final modeIndex = prefs.getInt(_modeKey) ?? ThemeMode.system.index;
    if (modeIndex >= 0 && modeIndex < ThemeMode.values.length) {
      _mode = ThemeMode.values[modeIndex];
    } else {
      _mode = ThemeMode.system;
    }

    final colorValue = prefs.getInt(_accentKey);
    if (colorValue != null) {
      final savedColor = Color(colorValue);
      _accent = Color.fromARGB(
        255,
        (savedColor.r * 255).round().clamp(0, 255),
        (savedColor.g * 255).round().clamp(0, 255),
        (savedColor.b * 255).round().clamp(0, 255),
      );
    } else {
      _accent = kDefaultAccent;
    }
    notifyListeners();
  }

  Future<void> setFontStyle(FontStyleOption option) async {
    _fontOption = option;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fontOptionKey, option.index);
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    _isEInkMode = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_modeKey, mode.index);
    await prefs.setBool(_isEInkKey, false);
  }

  Future<void> setAppThemeMode(AppThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    if (themeMode == AppThemeMode.eink) {
      _isEInkMode = true;
      await prefs.setBool(_isEInkKey, true);
    } else {
      _isEInkMode = false;
      await prefs.setBool(_isEInkKey, false);
      switch (themeMode) {
        case AppThemeMode.dark:
          _mode = ThemeMode.dark;
          break;
        case AppThemeMode.light:
          _mode = ThemeMode.light;
          break;
        case AppThemeMode.system:
          _mode = ThemeMode.system;
          break;
        case AppThemeMode.eink:
          break;
      }
      await prefs.setInt(_modeKey, _mode.index);
    }
    notifyListeners();
  }

  Future<void> setEInkMode(bool enabled) async {
    _isEInkMode = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isEInkKey, enabled);
  }

  Future<void> applyEInkPreset(EInkPreset preset) async {
    _einkAccent = preset.accentColor;
    _einkPaper = preset.paperColor;
    _isEInkMode = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isEInkKey, true);
    await prefs.setInt(_einkAccentKey, _einkAccent.toARGB32());
    await prefs.setInt(_einkPaperKey, _einkPaper.toARGB32());
  }

  Future<void> setEInkPreset(EInkPresetPalette preset) async {
    _einkPreset = preset;
    final config = EInkPalette.getConfig(preset);
    _einkPaper = config.background;
    _einkAccent = config.accent1;
    _isEInkMode = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isEInkKey, true);
    await prefs.setInt(_einkPresetKey, preset.index);
    await prefs.setInt(_einkPaperKey, _einkPaper.toARGB32());
    await prefs.setInt(_einkAccentKey, _einkAccent.toARGB32());
  }

  Future<void> setEInkAccentColor(Color color) async {
    _einkAccent = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_einkAccentKey, color.toARGB32());
  }

  Future<void> setEInkPaperColor(Color color) async {
    _einkPaper = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_einkPaperKey, color.toARGB32());
  }

  Future<void> setEInkRuledLines(bool enabled) async {
    _einkRuledLines = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_einkRuledKey, enabled);
  }

  Future<void> resetEInkPalette() async {
    await setEInkPreset(EInkPresetPalette.classicKaleido);
  }

  Future<void> setAccentColor(Color color) async {
    _accent = Color.fromARGB(
      255,
      (color.r * 255).round().clamp(0, 255),
      (color.g * 255).round().clamp(0, 255),
      (color.b * 255).round().clamp(0, 255),
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentKey, _accent.toARGB32());
  }

  Future<void> resetAccentColor() => setAccentColor(kDefaultAccent);

  ThemeData get darkTheme => _isEInkMode ? _buildEInkTheme() : _buildTheme(Brightness.dark, _accent, fontFamily);
  ThemeData get lightTheme => _isEInkMode ? _buildEInkTheme() : _buildTheme(Brightness.light, _accent, fontFamily);
  ThemeData get einkTheme => _buildEInkTheme();

  /// Builds the dedicated E-Ink Color Theme
  ThemeData _buildEInkTheme() {
    final config = EInkPalette.getConfig(_einkPreset);
    final background = _einkPaper;
    final surface = config.card;
    final foreground = config.text1;
    final mutedForeground = config.text2;
    final outline = config.border;
    final outlineVariant = config.border.withValues(alpha: 0.6);

    final palette = Eleven11AccentPalette(
      accentPrimary: _einkAccent,
      accentDark: Color.alphaBlend(foreground.withValues(alpha: 0.28), _einkAccent),
      accentLight: Color.alphaBlend(Colors.white.withValues(alpha: 0.28), _einkAccent),
      accentSoft: Color.alphaBlend(_einkAccent.withValues(alpha: 0.15), surface),
      accentBorder: Color.alphaBlend(_einkAccent.withValues(alpha: 0.45), outline),
      accentPressed: Color.alphaBlend(foreground.withValues(alpha: 0.18), _einkAccent),
    );

    final einkExt = Eleven11EInkExtension(
      isEInkMode: true,
      paperBackground: background,
      cardBackground: surface,
      inkColor: foreground,
      mutedInkColor: mutedForeground,
      subtleBorder: outline,
      highlightYellow: config.warning.withValues(alpha: 0.4),
      highlightGreen: config.success.withValues(alpha: 0.4),
      highlightOrange: config.accent1.withValues(alpha: 0.4),
      highlightPink: config.accent2.withValues(alpha: 0.4),
      highlightBlue: config.accent2.withValues(alpha: 0.4),
      ruledLineColor: outline.withValues(alpha: 0.5),
      showRuledLines: _einkRuledLines,
    );

    final colorScheme = ColorScheme.light(
      surface: surface,
      primary: palette.accentPrimary,
      onPrimary: background,
      primaryContainer: palette.accentSoft,
      onPrimaryContainer: foreground,
      secondary: config.accent2,
      onSecondary: background,
      secondaryContainer: Color.alphaBlend(config.accent2.withValues(alpha: 0.15), surface),
      onSecondaryContainer: foreground,
      tertiary: config.success,
      onTertiary: background,
      tertiaryContainer: Color.alphaBlend(config.success.withValues(alpha: 0.15), surface),
      onTertiaryContainer: foreground,
      error: config.accent1,
      onError: background,
      onSurface: foreground,
      onSurfaceVariant: mutedForeground,
      outline: outline,
      outlineVariant: outlineVariant,
    );

    final accentOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return palette.accentPressed.withValues(alpha: 0.18);
      }
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return palette.accentLight.withValues(alpha: 0.18);
      }
      return palette.accentSoft.withValues(alpha: 0.12);
    });

    final baseTextTheme = Typography.material2021(
      platform: TargetPlatform.android,
      colorScheme: colorScheme,
    ).black;

    return ThemeData(
      fontFamily: fontFamily,
      brightness: _einkPreset == EInkPresetPalette.nightEInk ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      extensions: [palette, einkExt],
      canvasColor: background,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline, width: 1.2),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: _einkPreset == EInkPresetPalette.nightEInk
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
        ),
        contentTextStyle: TextStyle(color: mutedForeground, fontFamily: fontFamily),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: outline),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: foreground, fontFamily: fontFamily),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: palette.accentSoft,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: mutedForeground, fontSize: 12, fontFamily: fontFamily),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? _einkAccent
                : mutedForeground,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: palette.accentPrimary,
        unselectedItemColor: mutedForeground,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: foreground),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(overlayColor: accentOverlay),
      ),
      textTheme: baseTextTheme.apply(
        fontFamily: fontFamily,
        bodyColor: foreground,
        displayColor: foreground,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: mutedForeground, fontFamily: fontFamily),
        labelStyle: TextStyle(color: mutedForeground, fontFamily: fontFamily),
        prefixIconColor: mutedForeground,
        suffixIconColor: mutedForeground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accentPrimary, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentPrimary
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentBorder
              : null,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentDark
              : outline,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accentPrimary,
        disabledActiveTrackColor: palette.accentDark,
        thumbColor: palette.accentPrimary,
        overlayColor: palette.accentSoft,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accentPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accentPrimary,
          foregroundColor: background,
          overlayColor: accentOverlay.resolve({WidgetState.pressed}),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          overlayColor: accentOverlay.resolve({WidgetState.pressed}),
          textStyle: TextStyle(fontFamily: fontFamily),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          overlayColor: accentOverlay.resolve({WidgetState.pressed}),
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(fontFamily: fontFamily),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: foreground, fontFamily: fontFamily),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: outline)),
      ),
    );
  }

  static ThemeData _buildTheme(Brightness brightness, Color accent, String? customFontFamily) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? kDarkBackground : kLightBackground;
    final surface = isDark ? kDarkSurface : kLightSurface;
    final foreground = isDark
        ? const Color(0xFFF5F1E8)
        : const Color(0xFF211D18);
    final mutedForeground = isDark
        ? const Color(0xFFB8B1A8)
        : const Color(0xFF6D665E);
    final outline = isDark ? const Color(0xFF3A3835) : const Color(0xFFE2DCCF);
    final outlineVariant = isDark
        ? const Color(0xFF29272D)
        : const Color(0xFFD8D1C4);
    final palette = Eleven11AccentPalette.fromColor(accent, surface);
    final error = isDark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E);
    final einkExt = Eleven11EInkExtension.standard(isEInk: false);

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: kSignatureGold,
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: palette.accentPrimary,
          onPrimary: foreground,
          primaryContainer: palette.accentSoft,
          onPrimaryContainer: foreground,
          secondary: kSignatureGold,
          onSecondary: kBrandDarkBackground,
          secondaryContainer: Color.alphaBlend(
            kSignatureGold.withValues(alpha: 0.16),
            surface,
          ),
          onSecondaryContainer: foreground,
          tertiary: kSignatureOrange,
          onTertiary: kBrandDarkBackground,
          tertiaryContainer: Color.alphaBlend(
            kSignatureOrange.withValues(alpha: 0.16),
            surface,
          ),
          onTertiaryContainer: foreground,
          error: error,
          onError: foreground,
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: mutedForeground,
          outline: outline,
          outlineVariant: outlineVariant,
          primaryFixed: palette.accentLight,
          primaryFixedDim: palette.accentPrimary,
          onPrimaryFixed: foreground,
          onPrimaryFixedVariant: mutedForeground,
          secondaryFixed: kSignatureGold,
          secondaryFixedDim: kSignatureGold,
          onSecondaryFixed: kBrandDarkBackground,
          onSecondaryFixedVariant: kBrandDarkBackground,
          tertiaryFixed: kSignatureOrange,
          tertiaryFixedDim: kSignatureOrange,
          onTertiaryFixed: kBrandDarkBackground,
          onTertiaryFixedVariant: kBrandDarkBackground,
        );

    final accentOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return palette.accentPressed.withValues(alpha: 0.18);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return palette.accentLight.withValues(alpha: 0.18);
      }
      return palette.accentSoft.withValues(alpha: 0.12);
    });

    final baseTextTheme = Typography.material2021(
      platform: TargetPlatform.android,
      colorScheme: colorScheme,
    ).black;

    return ThemeData(
      fontFamily: customFontFamily,
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      extensions: [palette, einkExt],
      canvasColor: background,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          fontFamily: customFontFamily,
        ),
        contentTextStyle: TextStyle(color: mutedForeground, fontFamily: customFontFamily),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: outline),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: foreground, fontFamily: customFontFamily),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: palette.accentSoft,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: mutedForeground, fontSize: 12, fontFamily: customFontFamily),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : mutedForeground,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: palette.accentPrimary,
        unselectedItemColor: mutedForeground,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: foreground),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(overlayColor: accentOverlay),
      ),
      textTheme: baseTextTheme.apply(
        fontFamily: customFontFamily,
        bodyColor: foreground,
        displayColor: foreground,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF191919) : const Color(0xFFFFFEFA),
        hintStyle: TextStyle(color: mutedForeground, fontFamily: customFontFamily),
        labelStyle: TextStyle(color: mutedForeground, fontFamily: customFontFamily),
        prefixIconColor: mutedForeground,
        suffixIconColor: mutedForeground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accentPrimary, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentPrimary
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentBorder
              : null,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentDark
              : outline,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accentPrimary,
        disabledActiveTrackColor: palette.accentDark,
        thumbColor: palette.accentPrimary,
        overlayColor: palette.accentSoft,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accentPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accentPrimary,
          foregroundColor: foreground,
          overlayColor: accentOverlay.resolve({WidgetState.pressed}),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(fontFamily: customFontFamily, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          overlayColor: accentOverlay.resolve({WidgetState.pressed}),
          textStyle: TextStyle(fontFamily: customFontFamily),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          overlayColor: accentOverlay.resolve({WidgetState.pressed}),
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(fontFamily: customFontFamily),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF302D29)
            : const Color(0xFF29251F),
        contentTextStyle: TextStyle(color: const Color(0xFFFFFCF5), fontFamily: customFontFamily),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
