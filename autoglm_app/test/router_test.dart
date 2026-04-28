import 'package:autoglm_core/autoglm_core.dart';
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
  testWidgets('router root path / redirects to /devices', (tester) async {
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
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/devices');
  });

  testWidgets('router exposes 5 top-level routes', (tester) async {
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
    await tester.pumpAndSettle();

    final paths = ['/devices', '/chat', '/workflows', '/history', '/settings'];
    for (final p in paths) {
      router.go(p);
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, p);
    }
  });
}
