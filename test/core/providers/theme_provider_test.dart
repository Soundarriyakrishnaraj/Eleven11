import 'package:eleven11/core/providers/theme_provider.dart';
import 'package:eleven11/core/theme/eink_palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _rgbAverage(Color color) {
  final value = color.toARGB32();
  final red = (value >> 16) & 0xFF;
  final green = (value >> 8) & 0xFF;
  final blue = value & 0xFF;
  return (red + green + blue) ~/ 3;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('theme selection is persisted and restored', () async {
    final notifier = ThemeNotifier();
    await notifier.load();

    expect(notifier.mode, ThemeMode.system);

    await notifier.setMode(ThemeMode.light);
    await notifier.setAccentColor(const Color(0xFF3F51B5));

    final restoredNotifier = ThemeNotifier();
    await restoredNotifier.load();

    expect(restoredNotifier.mode, ThemeMode.light);
    expect(restoredNotifier.accent, const Color(0xFF3F51B5));

    await restoredNotifier.setMode(ThemeMode.dark);
    final darkRestoredNotifier = ThemeNotifier();
    await darkRestoredNotifier.load();
    expect(darkRestoredNotifier.mode, ThemeMode.dark);
    expect(darkRestoredNotifier.accent, const Color(0xFF3F51B5));

    notifier.dispose();
    restoredNotifier.dispose();
    darkRestoredNotifier.dispose();
  });

  test('official brand colors stay fixed in both themes', () {
    final notifier = ThemeNotifier();

    expect(kBrandDarkBackground, const Color(0xFF0A090E));
    expect(kSignatureGold, const Color(0xFFE4BE69));
    expect(kSignatureOrange, const Color(0xFFF28C00));
    expect(notifier.darkTheme.scaffoldBackgroundColor, kBrandDarkBackground);
    expect(notifier.lightTheme.colorScheme.secondary, kSignatureGold);
    expect(notifier.darkTheme.colorScheme.tertiary, kSignatureOrange);
    expect(notifier.darkTheme.colorScheme.primary, kSignatureOrange);

    notifier.dispose();
  });

  test(
    'custom blue, purple, and green accents generate coordinated shades',
    () async {
      final notifier = ThemeNotifier();
      const accents = [Color(0xFF2962FF), Color(0xFF9C27B0), Color(0xFF4CAF50)];

      for (final accent in accents) {
        await notifier.setAccentColor(accent);

        final lightPalette = notifier.lightTheme
            .extension<Eleven11AccentPalette>()!;
        final darkPalette = notifier.darkTheme
            .extension<Eleven11AccentPalette>()!;

        expect(lightPalette.accentPrimary, accent);
        expect(darkPalette.accentPrimary, accent);
        expect(
          _rgbAverage(lightPalette.accentDark),
          lessThan(_rgbAverage(accent)),
        );
        expect(
          _rgbAverage(lightPalette.accentLight),
          greaterThan(_rgbAverage(accent)),
        );
        expect(lightPalette.accentSoft, isNot(darkPalette.accentSoft));
        expect(lightPalette.accentBorder, isNot(darkPalette.accentBorder));
        expect(
          _rgbAverage(lightPalette.accentPressed),
          lessThan(_rgbAverage(accent)),
        );
        expect(
          notifier.darkTheme.scaffoldBackgroundColor,
          kBrandDarkBackground,
        );
      }

      notifier.dispose();
    },
  );

  test(
    'custom accents do not change neutral text or fixed brand colors',
    () async {
      final notifier = ThemeNotifier();
      const accents = [Color(0xFF2962FF), Color(0xFF9C27B0), Color(0xFF4CAF50)];

      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final accent in accents) {
          await notifier.setAccentColor(accent);
          final theme = brightness == Brightness.dark
              ? notifier.darkTheme
              : notifier.lightTheme;

          expect(
            theme.colorScheme.onSurface,
            brightness == Brightness.dark
                ? const Color(0xFFF5F1E8)
                : const Color(0xFF211D18),
          );
          expect(
            theme.colorScheme.onSurfaceVariant,
            brightness == Brightness.dark
                ? const Color(0xFFB8B1A8)
                : const Color(0xFF6D665E),
          );
          expect(
            theme.colorScheme.onPrimary,
            brightness == Brightness.dark
                ? const Color(0xFFF5F1E8)
                : const Color(0xFF211D18),
          );
          expect(
            theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
            theme.colorScheme.onSurface,
          );
          expect(
            theme.textButtonTheme.style!.foregroundColor!.resolve({}),
            theme.colorScheme.onSurface,
          );
          expect(theme.colorScheme.primary, accent);
          expect(theme.colorScheme.secondary, kSignatureGold);
          expect(theme.colorScheme.tertiary, kSignatureOrange);
          expect(
            theme.colorScheme.error,
            brightness == Brightness.dark
                ? const Color(0xFFFF8A80)
                : const Color(0xFFB3261E),
          );
        }
      }

      notifier.dispose();
    },
  );

  testWidgets('theme selection updates MaterialApp immediately', (
    tester,
  ) async {
    final notifier = ThemeNotifier();
    await notifier.load();
    await notifier.setMode(ThemeMode.dark);

    await tester.pumpWidget(_ThemePreviewApp(notifier: notifier));
    expect(find.text('dark'), findsOneWidget);

    await notifier.setMode(ThemeMode.light);
    expect(notifier.mode, ThemeMode.light);
    await tester.pumpAndSettle();

    expect(find.text('light'), findsOneWidget);
    notifier.dispose();
  });

  test('E-Ink Color Theme selection, presets, and preferences persistence', () async {
    final notifier = ThemeNotifier();
    await notifier.load();

    expect(notifier.isEInkMode, false);

    // Enable E-Ink mode
    await notifier.setEInkMode(true);
    expect(notifier.isEInkMode, true);
    expect(notifier.appThemeMode, AppThemeMode.eink);

    // Verify einkTheme properties
    final einkTheme = notifier.einkTheme;
    expect(einkTheme.brightness, Brightness.light);
    expect(einkTheme.scaffoldBackgroundColor, notifier.einkPaper);
    expect(einkTheme.colorScheme.onSurface, EInkPalette.classicKaleido.text1);

    // Apply E-Ink preset
    await notifier.applyEInkPreset(EInkPresets.warmPaper);
    expect(notifier.einkAccent, EInkPresets.warmPaper.accentColor);
    expect(notifier.einkPaper, EInkPresets.warmPaper.paperColor);

    // Toggle ruled lines
    await notifier.setEInkRuledLines(true);
    expect(notifier.einkRuledLines, true);

    // Persistence test
    final restored = ThemeNotifier();
    await restored.load();
    expect(restored.isEInkMode, true);
    expect(restored.einkAccent, EInkPresets.warmPaper.accentColor);
    expect(restored.einkPaper, EInkPresets.warmPaper.paperColor);
    expect(restored.einkRuledLines, true);

    // Reset to defaults
    await restored.resetEInkPalette();
    expect(restored.einkAccent, EInkPalette.classicKaleido.accent1);

    // Font style option tests
    expect(restored.fontOption, FontStyleOption.normal);
    expect(restored.isUppercaseMode, false);
    expect(restored.fontFamily, null);

    await restored.setFontStyle(FontStyleOption.customTTF);
    expect(restored.fontOption, FontStyleOption.customTTF);
    expect(restored.isUppercaseMode, true);
    expect(restored.fontFamily, 'MyHandwriting');

    final fontRestored = ThemeNotifier();
    await fontRestored.load();
    expect(fontRestored.fontOption, FontStyleOption.customTTF);
    expect(fontRestored.isUppercaseMode, true);
    expect(fontRestored.fontFamily, 'MyHandwriting');

    // Switching back to normal mode turns off E-Ink
    await restored.setMode(ThemeMode.dark);
    expect(restored.isEInkMode, false);
    expect(restored.mode, ThemeMode.dark);

    notifier.dispose();
    restored.dispose();
    fontRestored.dispose();
  });
}

class _ThemePreviewApp extends StatelessWidget {
  const _ThemePreviewApp({required this.notifier});

  final ThemeNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => MaterialApp(
        theme: notifier.lightTheme,
        darkTheme: notifier.darkTheme,
        themeMode: notifier.mode,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Text(
                Theme.of(context).brightness == Brightness.dark
                    ? 'dark'
                    : 'light',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
