import 'package:autoglm_desktop/app.dart';
import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(LocaleSettings.useDeviceLocale);

  Future<void> go(WidgetTester tester, String path) async {
    final router = createRouter()..go(path);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sidebar visible on /devices', (tester) async {
    await go(tester, '/devices');
    expect(find.byKey(AppShell.deviceSidebarKey), findsOneWidget);
  });

  testWidgets('sidebar visible on /chat', (tester) async {
    await go(tester, '/chat');
    expect(find.byKey(AppShell.deviceSidebarKey), findsOneWidget);
  });

  testWidgets('sidebar hidden on /workflows', (tester) async {
    await go(tester, '/workflows');
    expect(find.byKey(AppShell.deviceSidebarKey), findsNothing);
  });

  testWidgets('sidebar hidden on /history', (tester) async {
    await go(tester, '/history');
    expect(find.byKey(AppShell.deviceSidebarKey), findsNothing);
  });

  testWidgets('sidebar hidden on /settings', (tester) async {
    await go(tester, '/settings');
    expect(find.byKey(AppShell.deviceSidebarKey), findsNothing);
  });
}
