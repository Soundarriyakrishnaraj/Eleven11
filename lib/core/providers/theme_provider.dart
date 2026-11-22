import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kBrandDarkBackground = Color(0xFF0A090E);
const Color kSignatureGold = Color(0xFFE4BE69);
const Color kSignatureOrange = Color(0xFFF28C00);
const Color kDefaultAccent = kSignatureOrange;
const Color kDarkBackground = kBrandDarkBackground;
const Color kDarkSurface = Color(0xFF222222);
const Color kLightBackground = Color(0xFFF7F2E8);
const Color kLightSurface = Color(0xFFFFFCF5);

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

  ThemeMode _mode = ThemeMode.system;
  Color _accent = kDefaultAccent;

  ThemeMode get mode => _mode;
  Color get accent => _accent;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
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

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_modeKey, mode.index);
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

  ThemeData get darkTheme => _buildTheme(Brightness.dark, _accent);
  ThemeData get lightTheme => _buildTheme(Brightness.light, _accent);

  static ThemeData _buildTheme(Brightness brightness, Color accent) {
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

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      extensions: [palette],
      canvasColor: background,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
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
        ),
        contentTextStyle: TextStyle(color: mutedForeground),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: foreground),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: palette.accentSoft,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: mutedForeground, fontSize: 12),
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
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: palette.accentSoft,
        checkmarkColor: palette.accentPrimary,
        side: BorderSide(color: outline),
        labelStyle: TextStyle(color: foreground),
        secondaryLabelStyle: TextStyle(color: foreground),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: foreground,
        unselectedLabelColor: mutedForeground,
        indicatorColor: palette.accentBorder,
        dividerColor: outline,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentPrimary
              : null,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentPrimary
              : null,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.accentPrimary,
        selectionColor: palette.accentSoft,
        selectionHandleColor: palette.accentPrimary,
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: foreground),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(overlayColor: accentOverlay),
      ),
      textTheme: Typography.material2021(
        platform: TargetPlatform.android,
        colorScheme: colorScheme,
      ).black.apply(bodyColor: foreground, displayColor: foreground),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF191919) : const Color(0xFFFFFEFA),
        hintStyle: TextStyle(color: mutedForeground),
        labelStyle: TextStyle(color: mutedForeground),
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
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          overlayColor: accentOverlay.resolve({WidgetState.pressed}),
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
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF302D29)
            : const Color(0xFF29251F),
        contentTextStyle: const TextStyle(color: Color(0xFFFFFCF5)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
