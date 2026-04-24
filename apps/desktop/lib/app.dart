import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/theme_mode_provider.dart';
import 'package:autoglm_desktop/router.dart';
import 'package:autoglm_ui_kit/autoglm_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The root widget of the AutoGLM application.
class AutoGLMApp extends ConsumerWidget {
  /// Creates an [AutoGLMApp].
  const AutoGLMApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'AutoGLM',
      themeMode: themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      routerConfig: createRouter(),
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

/// Application shell with a 5-destination [NavigationRail].
class AppShell extends StatelessWidget {
  /// Creates an [AppShell] that wraps the current route [child].
  const AppShell({required this.child, super.key});

  /// The current route content rendered by the enclosing shell route.
  final Widget child;

  /// Routes that show the device sidebar.
  static const _sidebarRoutes = {'/devices', '/chat'};

  static const _routes = [
    '/devices',
    '/chat',
    '/workflows',
    '/history',
    '/settings',
  ];

  /// Test hook: locates the device sidebar in the widget tree.
  static const deviceSidebarKey = ValueKey('app-shell.device-sidebar');

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final i = _routes.indexWhere(location.startsWith);
    return i < 0 ? 0 : i;
  }

  bool _showSidebar(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return _sidebarRoutes.any(location.startsWith);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex(context);
    final showSidebar = _showSidebar(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: (i) => context.go(_routes[i]),
            labelType: NavigationRailLabelType.all,
            backgroundColor: theme.colorScheme.surfaceContainerLow,
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.smartphone_outlined),
                selectedIcon: const Icon(Icons.smartphone),
                label: Text(t.nav.devices),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.chat_outlined),
                selectedIcon: const Icon(Icons.chat),
                label: Text(t.nav.chat),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.playlist_play_outlined),
                selectedIcon: const Icon(Icons.playlist_play),
                label: Text(t.nav.workflows),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.history_outlined),
                selectedIcon: const Icon(Icons.history),
                label: Text(t.nav.history),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: Text(t.nav.settings),
              ),
            ],
          ),
          if (showSidebar) ...[
            Container(
              key: deviceSidebarKey,
              width: 280,
              color: theme.colorScheme.surfaceContainer,
              child: const Padding(
                padding: AppSpacing.edgeInsetsMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Devices',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Device sidebar content',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            VerticalDivider(
              thickness: 1,
              width: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}
