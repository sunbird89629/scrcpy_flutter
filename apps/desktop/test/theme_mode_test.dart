import 'dart:async';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_desktop/providers/settings_provider.dart';
import 'package:autoglm_desktop/providers/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySettingsRepository implements SettingsRepository {
  Settings _current = const Settings();

  @override
  Future<Settings> load() async => _current;

  @override
  Future<void> save(Settings settings) async {
    _current = settings;
  }
}

void main() {
  testWidgets('themeModeProvider derives from settings.themeMode',
      (tester) async {
    final repo = _MemorySettingsRepository();
    unawaited(repo.save(const Settings(themeMode: ThemeMode.dark)));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return MaterialApp(
              themeMode: mode,
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              home: Scaffold(body: Text(mode.name)),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsOneWidget);
  });
}
