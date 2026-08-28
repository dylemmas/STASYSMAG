import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/connection_screen.dart';
import '../screens/ota_update_screen.dart';
import '../screens/main_shell.dart';
import '../screens/tracking_screen.dart';
import '../screens/history_screen.dart';
import '../screens/settings_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/connection',
      builder: (context, state) => const ConnectionScreen(),
    ),
    GoRoute(
      path: '/ota-update',
      builder: (context, state) => const OtaUpdateScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/tracking',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TrackingScreen(),
          ),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HistoryScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),
  ],
);
