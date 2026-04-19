import 'package:autoglm_core/autoglm_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Settings', () {
    test('default values match spec', () {
      const s = Settings();
      expect(s.themeMode, ThemeMode.system);
      expect(s.locale, 'system');
      expect(s.llmBaseUrl, 'https://open.bigmodel.cn/api/paas/v4');
      expect(s.llmModel, 'autoglm-phone');
      expect(s.llmApiKey, '');
      expect(s.mcpServerEnabled, isFalse);
      expect(s.mcpServerPort, 8765);
    });

    test('toJson/fromJson roundtrip preserves all fields', () {
      const original = Settings(
        themeMode: ThemeMode.dark,
        locale: 'zh-CN',
        llmBaseUrl: 'http://example.com/v1',
        llmModel: 'gpt-4',
        llmApiKey: 'sk-xxx',
        mcpServerEnabled: true,
        mcpServerPort: 9000,
      );
      final json = original.toJson();
      final decoded = Settings.fromJson(json);
      expect(decoded, equals(original));
    });

    test('fromJson with missing fields uses defaults', () {
      final s = Settings.fromJson(const <String, dynamic>{});
      expect(s, equals(const Settings()));
    });

    test('copyWith updates one field', () {
      const s = Settings();
      final updated = s.copyWith(llmApiKey: 'new-key');
      expect(updated.llmApiKey, 'new-key');
      expect(updated.themeMode, ThemeMode.system);
    });
  });
}
