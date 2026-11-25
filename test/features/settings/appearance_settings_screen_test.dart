import 'package:eleven11/core/providers/theme_provider.dart';
import 'package:eleven11/features/settings/screens/appearance_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeNotifier.instance.load();
    await ThemeNotifier.instance.setMode(ThemeMode.dark);
    await ThemeNotifier.instance.setAccentColor(kDefaultAccent);
  });

  testWidgets('HEX and RGB controls apply the accent globally', (tester) async {
    final notifier = ThemeNotifier.instance;
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: notifier,
        builder: (context, _) => MaterialApp(
          theme: notifier.lightTheme,
          darkTheme: notifier.darkTheme,
          themeMode: notifier.mode,
          home: Builder(
            builder: (context) => Column(
              children: [
                Text(
                  Theme.of(context).colorScheme.primary
                      .toARGB32()
                      .toRadixString(16),
                  key: const ValueKey('global-accent'),
                ),
                const Expanded(child: AppearanceSettingsScreen()),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('APPLY ACCENT COLOR'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final hexField = find.byType(TextField);
    await tester.enterText(hexField, '2962FF');
    expect(tester.widget<TextField>(hexField).controller!.text, '2962FF');
    await tester.tap(find.text('APPLY ACCENT COLOR'));
    await tester.pumpAndSettle();
    expect(notifier.accent, const Color(0xFF2962FF));
    expect(notifier.darkTheme.colorScheme.primary, const Color(0xFF2962FF));
    expect(find.text('ff2962ff'), findsOneWidget);

    final redSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('red-slider')),
    );
    final greenSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('green-slider')),
    );
    final blueSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('blue-slider')),
    );
    redSlider.onChanged!(10);
    greenSlider.onChanged!(20);
    blueSlider.onChanged!(30);
    await tester.pump();

    expect(tester.widget<TextField>(hexField).controller!.text, '#0A141E');
    await tester.scrollUntilVisible(
      find.text('APPLY ACCENT COLOR'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('APPLY ACCENT COLOR'));
    await tester.pumpAndSettle();
    expect(notifier.accent, const Color(0xFF0A141E));
    expect(
      notifier.darkTheme.extension<Eleven11AccentPalette>()!.accentPrimary,
      const Color(0xFF0A141E),
    );
    expect(find.text('ff0a141e'), findsOneWidget);
  });
}
