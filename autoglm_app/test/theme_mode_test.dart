import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_app/providers/settings_provider.dart';
import 'package:autoglm_app/providers/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRepo implements SettingsRepository {
  _MemoryRepo([this.initial = const Settings()]);
  Settings initial;
  @override
  Future<Settings> load() async => initial;
  @override
  Future<void> save(Settings s) async => initial = s;
}

void main() {
  group('themeModeProvider', () {
    test('derives from settings.themeMode', () async {
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _MemoryRepo(const Settings(themeMode: 'dark')),
          ),
        ],
      );

      // Wait for settings to load
      await container.read(settingsProvider.future);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
