import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/theme_mode_provider.dart';
import 'package:autoglm_desktop/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _themeSeedColor = Colors.deepPurple;

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _themeSeedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _themeSeedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: createRouter(),
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

/// Application shell with a 5-destination [NavigationRail].
///
/// Wraps the current route [child] in a [Scaffold] whose body is a [Row]
/// of a [NavigationRail] and the routed content. The selected destination
/// is derived from [GoRouterState], and tapping a destination calls
/// [GoRouter.go] to navigate.
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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: (i) => context.go(_routes[i]),
            labelType: NavigationRailLabelType.all,
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.smartphone),
                label: Text(t.nav.devices),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.chat),
                label: Text(t.nav.chat),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.playlist_play),
                label: Text(t.nav.workflows),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.history),
                label: Text(t.nav.history),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings),
                label: Text(t.nav.settings),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          if (showSidebar) ...[
            Container(
              key: deviceSidebarKey,
              width: 240,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              alignment: Alignment.center,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Device sidebar',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}
