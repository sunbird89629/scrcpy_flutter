import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_app/i18n/strings.g.dart';
import 'package:autoglm_app/providers/adb_provider.dart';
import 'package:autoglm_app/providers/settings_provider.dart';
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
  testWidgets('localeApplyProvider wires into widget tree', (tester) async {
    final repo = _MemoryRepo(const Settings(locale: 'zh-CN'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
          adbDevicesProvider.overrideWith((ref) => ['test-device']),
        ],
        child: TranslationProvider(
          child: Consumer(
            builder: (context, ref, child) {
              // Trigger watch
              ref.watch(settingsProvider);
              return const MaterialApp(home: Scaffold(body: Text('hello')));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final element = tester.element(find.text('hello'));
    final locale = TranslationProvider.of(element).locale;
    expect(locale.languageCode, 'zh');
  });
}
