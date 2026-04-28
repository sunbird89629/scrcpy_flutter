import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_app/i18n/strings.g.dart';
import 'package:autoglm_app/pages/settings_page.dart';
import 'package:autoglm_app/providers/settings_provider.dart';
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
  setUpAll(LocaleSettings.useDeviceLocale);

  Future<void> pump(WidgetTester tester, _MemoryRepo repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
        child: TranslationProvider(
          child: const MaterialApp(home: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders theme + locale labels', (tester) async {
    await pump(tester, _MemoryRepo());
    expect(find.text(t.settings.theme.label), findsWidgets);
    expect(find.text(t.settings.locale.label), findsWidgets);
  });

  testWidgets('changing theme dropdown persists to repo', (tester) async {
    final repo = _MemoryRepo();
    await pump(tester, repo);

    await tester.tap(find.byKey(SettingsPage.themeDropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.theme.dark).last);
    await tester.pumpAndSettle();

    final saved = await repo.load();
    expect(saved.themeMode, ThemeMode.dark);
  });

  testWidgets('changing locale dropdown persists to repo', (tester) async {
    final repo = _MemoryRepo();
    await pump(tester, repo);

    await tester.tap(find.byKey(SettingsPage.localeDropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('en-US').last);
    await tester.pumpAndSettle();

    final saved = await repo.load();
    expect(saved.locale, 'en-US');
  });
}
