import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:eleven11/features/notifications/notification_service.dart';
import 'package:eleven11/features/notifications/services/notification_navigation.dart';

import 'config/app_config.dart';
import 'core/providers/theme_provider.dart';
import 'firebase_options.dart';
import 'features/authentication/auth_gate_auth_state.dart';
import 'features/authentication/login_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/motivation/screens/motivation_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.queueBackgroundFcmMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  await ThemeNotifier.instance.load();

  runApp(const ProviderScope(child: Eleven11App()));

  unawaited(
    NotificationService.instance.initialize().catchError((error, stackTrace) {
      debugPrint('Notification initialization failed: $error');
    }),
  );
}

class Eleven11App extends StatelessWidget {
  const Eleven11App({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeNotifier.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: NotificationNavigation.navigatorKey,
          title: 'Eleven11',
          debugShowCheckedModeBanner: false,
          theme: ThemeNotifier.instance.lightTheme,
          darkTheme: ThemeNotifier.instance.darkTheme,
          themeMode: ThemeNotifier.instance.mode,
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authGateAuthState = AuthGateAuthState();
  AuthState? _authState;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (!mounted) return;
      setState(() {
        _authGateAuthState.update(state);
        _authState = state;
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _hasCompletedOnboarding(String userId) async {
    final result = await Supabase.instance.client
        .from('user_onboarding')
        .select('completed_at')
        .eq('user_id', userId)
        .maybeSingle();

    return result != null && result['completed_at'] != null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = _authState;
    if (_authGateAuthState.shouldShowLogin(authState)) {
      return const LoginScreen();
    }

    final user =
        authState?.session?.user ?? Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const LoginScreen();
    }

    return FutureBuilder<bool>(
      key: ValueKey(user.id),
      future: _hasCompletedOnboarding(user.id),
      builder: (context, onboardingSnapshot) {
        if (onboardingSnapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (onboardingSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Unable to load your profile.')),
          );
        }

        if (onboardingSnapshot.data == true) {
          return const MotivationScreen();
        }

        return OnboardingScreen(
          onCompleted: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MotivationScreen()),
            );
          },
        );
      },
    );
  }
}
