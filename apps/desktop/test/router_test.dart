import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/settings_provider.dart';
import 'package:autoglm_desktop/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MemoryRepo implements SettingsRepository {
  Settings _current = const Settings();
  @override
  Future<Settings> load() async => _current;
  @override
  Future<void> save(Settings s) async => _current = s;
}

void main() {
  setUpAll(LocaleSettings.useDeviceLocale);

  Widget appWith(GoRouter router) {
    return ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(_MemoryRepo()),
      ],
      child: TranslationProvider(
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
  }

  group('router', () {
    testWidgets('root path / redirects to /devices', (tester) async {
      final router = createRouter();
      await tester.pumpWidget(appWith(router));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/devices');
    });

    testWidgets('exposes 5 top-level routes', (tester) async {
      final router = createRouter();
      await tester.pumpWidget(appWith(router));
      await tester.pumpAndSettle();
      const expected = [
        '/devices',
        '/chat',
        '/workflows',
        '/history',
        '/settings',
      ];
      for (final path in expected) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          path,
          reason: 'route $path should be navigable',
        );
      }
    });
  });
}
