import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_app/app.dart';
import 'package:autoglm_app/providers/adb_provider.dart';
import 'package:autoglm_app/providers/settings_provider.dart';
import 'package:autoglm_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRepo implements SettingsRepository {
  Settings _current = const Settings();
  @override
  Future<Settings> load() async => _current;
  @override
  Future<void> save(Settings s) async => _current = s;
}

void main() {
  Future<void> go(WidgetTester tester, String path) async {
    final router = createRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(_MemoryRepo()),
          adbDevicesProvider.overrideWith((ref) => ['test-device']),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go(path);
    await tester.pumpAndSettle();
  }

  testWidgets('sidebar visible on /devices', (tester) async {
    await go(tester, '/devices');
    expect(find.byKey(AppShell.deviceSidebarKey), findsOneWidget);
  });

  testWidgets('sidebar hidden on /settings', (tester) async {
    await go(tester, '/settings');
    expect(find.byKey(AppShell.deviceSidebarKey), findsNothing);
  });
}
