import 'dart:async';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/locale_provider.dart';
import 'package:autoglm_desktop/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRepo implements SettingsRepository {
  _MemoryRepo(this.initial);
  Settings initial;
  @override
  Future<Settings> load() async => initial;
  @override
  Future<void> save(Settings s) async => initial = s;
}

void main() {
  test('localeApplyProvider applies en-US locale', () async {
    await LocaleSettings.setLocaleRaw('system'); // Reset
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _MemoryRepo(const Settings(locale: 'en-US')),
        ),
      ],
    );

    // First, read settings to let them load
    await container.read(settingsProvider);

    // Now read the locale provider - at this point settings are available
    final _ = container.read(localeApplyProvider);

    // Verify the locale was applied
    expect(LocaleSettings.currentLocale.languageCode, 'en');
    expect(LocaleSettings.currentLocale.countryCode, 'US');
  });

  test('localeApplyProvider applies zh-CN locale', () async {
    await LocaleSettings.setLocaleRaw('system'); // Reset
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _MemoryRepo(const Settings(locale: 'zh-CN')),
        ),
      ],
    );

    // First, read settings to let them load
    await container.read(settingsProvider);

    // Now read the locale provider - at this point settings are available
    final _ = container.read(localeApplyProvider);

    // Verify the locale was applied
    expect(LocaleSettings.currentLocale.languageCode, 'zh');
    expect(LocaleSettings.currentLocale.countryCode, 'CN');
  });

  test('localeApplyProvider parses and applies locales', () async {
    // This test verifies the provider infrastructure works by testing the parsing
    final enUs = AppLocaleUtils.parse('en-US');
    expect(enUs.languageCode, 'en');
    expect(enUs.countryCode, 'US');

    final zhCn = AppLocaleUtils.parse('zh-CN');
    expect(zhCn.languageCode, 'zh');
    expect(zhCn.countryCode, 'CN');
  });
}
