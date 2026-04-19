import 'dart:io';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('JsonFileSettingsRepository', () {
    late Directory tmp;
    late File file;
    late JsonFileSettingsRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('settings_test_');
      file = File(p.join(tmp.path, 'settings.json'));
      repo = JsonFileSettingsRepository(file);
    });

    tearDown(() async {
      if (tmp.existsSync()) {
        await tmp.delete(recursive: true);
      }
    });

    test('load returns defaults when file does not exist', () async {
      expect(file.existsSync(), isFalse);
      final s = await repo.load();
      expect(s, equals(const Settings()));
    });

    test('save then load returns the same settings', () async {
      const original = Settings(
        themeMode: ThemeMode.dark,
        locale: 'en-US',
        llmApiKey: 'sk-test',
        mcpServerEnabled: true,
      );
      await repo.save(original);
      final loaded = await repo.load();
      expect(loaded, equals(original));
    });

    test('save creates parent directories if missing', () async {
      final nested =
          File(p.join(tmp.path, 'a', 'b', 'c', 'settings.json'));
      final nestedRepo = JsonFileSettingsRepository(nested);
      await nestedRepo.save(const Settings(locale: 'zh-CN'));
      expect(nested.existsSync(), isTrue);
      final loaded = await nestedRepo.load();
      expect(loaded.locale, 'zh-CN');
    });

    test('load returns defaults if file is corrupted JSON', () async {
      await file.writeAsString('{not valid json');
      final s = await repo.load();
      expect(s, equals(const Settings()));
    });
  });
}
