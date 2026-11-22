import 'package:eleven11/features/authentication/logout_icon_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logout asks for confirmation and Cancel stays on Home', (
    tester,
  ) async {
    var signOutCalls = 0;
    final navigatorKey = await _pumpHome(
      tester,
      signOut: () async {
        signOutCalls++;
      },
    );

    await tester.tap(find.byTooltip('Logout'));
    await tester.pumpAndSettle();

    expect(find.text('Log out?'), findsOneWidget);
    expect(
      find.text('Are you sure you want to log out of Eleven11?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(signOutCalls, 0);
    expect(find.text('Home screen'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isTrue);
  });

  testWidgets('confirmed logout signs out and clears the Home route', (
    tester,
  ) async {
    var signOutCalls = 0;
    final navigatorKey = await _pumpHome(
      tester,
      signOut: () async {
        signOutCalls++;
      },
    );

    await tester.tap(find.byTooltip('Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    expect(signOutCalls, 1);
    expect(find.text('Login screen'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
  });

  testWidgets('sign-out failure keeps Home open and reports the error', (
    tester,
  ) async {
    final navigatorKey = await _pumpHome(
      tester,
      signOut: () async => throw StateError('offline'),
    );

    await tester.tap(find.byTooltip('Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    expect(find.text('Home screen'), findsOneWidget);
    expect(
      find.textContaining('Logout failed: Bad state: offline'),
      findsOneWidget,
    );
    expect(navigatorKey.currentState!.canPop(), isTrue);
  });
}

Future<GlobalKey<NavigatorState>> _pumpHome(
  WidgetTester tester, {
  required Future<void> Function() signOut,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('Login screen')),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(actions: [LogoutIconButton(signOut: signOut)]),
        body: const Text('Home screen'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigatorKey;
}
