import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUpAll(LocaleSettings.useDeviceLocale);

  Widget appWith(GoRouter router) {
    return TranslationProvider(
      child: MaterialApp.router(
        routerConfig: router,
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
