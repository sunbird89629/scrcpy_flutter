import 'dart:io';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonFileSettingsRepository', () {
    late Directory tempDir;
    late String filePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('settings_test');
      filePath = '${tempDir.path}/settings.json';
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('load returns defaults when file does not exist', () async {
      final repo = JsonFileSettingsRepository(filePath: filePath);
      final settings = await repo.load();
      expect(settings.themeMode, 'system');
    });

    test('save then load returns the same settings', () async {
      final repo = JsonFileSettingsRepository(filePath: filePath);
      const settings = Settings(themeMode: 'dark', llmApiKey: 'test-key');

      await repo.save(settings);
      final loaded = await repo.load();
      expect(loaded.themeMode, 'dark');
      expect(loaded.llmApiKey, 'test-key');
    });
  });
}
