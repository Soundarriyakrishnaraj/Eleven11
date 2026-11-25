import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:eleven11/features/notifications/notification_service.dart';
import 'package:eleven11/features/notifications/services/notification_navigation.dart';

import 'config/app_config.dart';
import 'core/providers/theme_provider.dart';
import 'core/security/app_lock_service.dart';
import 'core/security/app_lock_screen.dart';
import 'core/security/user_activity_tracker.dart';
import 'features/feedback/screens/feedback_screen.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/admin/screens/admin_users_screen.dart';
import 'features/admin/screens/admin_feedback_screen.dart';
import 'firebase_options.dart';
import 'features/authentication/auth_gate_auth_state.dart';
import 'features/authentication/login_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/motivation/screens/motivation_screen.dart';
import 'features/dashboard/dashboard_screen.dart';

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
  await AppLockService.instance.initialize();

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
      listenable: Listenable.merge([ThemeNotifier.instance, AppLockService.instance]),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: NotificationNavigation.navigatorKey,
          title: 'Eleven11',
          debugShowCheckedModeBanner: false,
          theme: ThemeNotifier.instance.lightTheme,
          darkTheme: ThemeNotifier.instance.darkTheme,
          themeMode: ThemeNotifier.instance.mode,
          builder: (context, child) {
            return Stack(
              children: [
                ?child,
                if (AppLockService.instance.isLocked)
                  const Positioned.fill(
                    child: AppLockScreen(),
                  ),
              ],
            );
          },
          home: const AuthGate(),
          routes: {
            '/feedback': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              final initialCategory = args is String ? args : null;
              return FeedbackScreen(initialCategory: initialCategory);
            },
            '/admin': (context) => const AdminDashboardScreen(),
            '/admin/users': (context) => const AdminUsersScreen(),
            '/admin/feedback': (context) => const AdminFeedbackScreen(),
          },
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
  String? _lastAuthenticatedUserId;

  @override
  void initState() {
    super.initState();
    final initialUser = Supabase.instance.client.auth.currentUser;
    if (initialUser != null) {
      _lastAuthenticatedUserId = initialUser.id;
      UserActivityTracker.instance.recordHeartbeat();
    }

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      final sessionUser = state.session?.user;
      if (sessionUser != null) {
        _lastAuthenticatedUserId = sessionUser.id;
        if (state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.initialSession) {
          UserActivityTracker.instance.recordHeartbeat();
        }
      } else if (state.event == AuthChangeEvent.signedOut) {
        final previousUserId = _lastAuthenticatedUserId;
        _lastAuthenticatedUserId = null;
        // Only record session_expired when sign-out was NOT user-initiated.
        if (previousUserId != null &&
            !UserActivityTracker.instance.isExplicitSignOutInProgress) {
          UserActivityTracker.instance.recordSessionExpired(previousUserId);
        }
      }

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

  Future<({bool completed, String startScreen})> _resolveLanding(
    String userId,
  ) async {
    final result = await Supabase.instance.client
        .from('user_onboarding')
        .select('completed_at')
        .eq('user_id', userId)
        .maybeSingle();

    final prefs = await SharedPreferences.getInstance();
    final startScreen = prefs.getString('pref_start_screen') ?? 'Dashboard';

    return (
      completed: result != null && result['completed_at'] != null,
      startScreen: startScreen,
    );
  }

  Widget _buildLandingScreen(String startScreen) {
    return DashboardScreen(initialLandingScreen: startScreen);
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

    return FutureBuilder<({bool completed, String startScreen})>(
      key: ValueKey(user.id),
      future: _resolveLanding(user.id),
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

        final data = onboardingSnapshot.data;
        if (data != null && data.completed) {
          return _buildLandingScreen(data.startScreen);
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
