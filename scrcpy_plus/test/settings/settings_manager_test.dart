import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';

void main() {
  late Directory tempDir;
  late SettingsManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('scrcpy_plus_test_');
    manager = SettingsManager(configDir: tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SettingsManager', () {
    test('loadConfig returns defaults when no file exists', () async {
      final config = await manager.loadConfig();
      expect(config.scrcpyPath, 'scrcpy');
      expect(config.maxSize, 1024);
    });

    test('saveConfig then loadConfig round-trips', () async {
      const config = ScrcpyConfig(
        scrcpyPath: '/usr/local/bin/scrcpy',
        maxSize: 1280,
        videoBitRate: '4M',
        videoCodec: 'h265',
      );
      await manager.saveConfig(config);
      final loaded = await manager.loadConfig();
      expect(loaded.scrcpyPath, '/usr/local/bin/scrcpy');
      expect(loaded.maxSize, 1280);
      expect(loaded.videoBitRate, '4M');
      expect(loaded.videoCodec, 'h265');
    });

    test('loadKnownSerials returns empty list when no file', () async {
      final serials = await manager.loadKnownSerials();
      expect(serials, isEmpty);
    });

    test('saveKnownSerials then loadKnownSerials round-trips', () async {
      await manager.saveKnownSerials(['dev1', 'dev2']);
      final loaded = await manager.loadKnownSerials();
      expect(loaded, ['dev1', 'dev2']);
    });
  });
}
