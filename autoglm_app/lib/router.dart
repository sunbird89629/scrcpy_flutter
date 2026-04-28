import 'package:autoglm_app/app.dart';
import 'package:autoglm_app/pages/chat_page.dart';
import 'package:autoglm_app/pages/devices_page.dart';
import 'package:autoglm_app/pages/history_page.dart';
import 'package:autoglm_app/pages/settings_page.dart';
import 'package:autoglm_app/pages/workflows_page.dart';
import 'package:go_router/go_router.dart';

/// Creates the application [GoRouter].
///
/// Declares five top-level routes (`/devices`, `/chat`, `/workflows`,
/// `/history`, `/settings`) nested under a [ShellRoute] that renders
/// the [AppShell]. The initial location is `/devices`.
GoRouter createRouter() {
  return GoRouter(
    initialLocation: '/devices',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/devices',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: DevicesPage()),
          ),
          GoRoute(
            path: '/chat',
            pageBuilder: (_, __) => const NoTransitionPage(child: ChatPage()),
          ),
          GoRoute(
            path: '/workflows',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: WorkflowsPage()),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: HistoryPage()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
    ],
  );
}
