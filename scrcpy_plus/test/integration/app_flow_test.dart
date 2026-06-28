import 'dart:io';

import 'package:adb_tools/adb_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/app/menu_builder.dart';
import 'package:scrcpy_plus/device/device_entry.dart';
import 'package:scrcpy_plus/device/device_group.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';

DeviceGroup _group(DeviceEntry e) => DeviceGroup(
  physicalSerial: e.info.physicalSerial,
  displayName: e.displayName,
  connections: [e],
);

void main() {
  group('Integration: full flow', () {
    test('menu builds correctly with mixed devices', () {
      final groups = [
        _group(
          DeviceEntry(
            info: const DeviceInfo(
              serial: '192.168.1.100:5555',
              status: DeviceStatus.online,
              model: 'Pixel 7',
              androidVersion: '14',
              screenWidth: 1080,
              screenHeight: 2400,
            ),
            battery: 85,
          ),
        ),
        _group(
          DeviceEntry(
            info: const DeviceInfo(
              serial: 'ABCD1234',
              status: DeviceStatus.online,
              model: 'Samsung S23',
            ),
          ),
        ),
      ];

      final menu = MenuBuilder.buildMenu(groups: groups);
      final keys = menu.items!.map((i) => i.key).toList();

      expect(keys, contains('launch_192.168.1.100:5555'));
      expect(keys, contains('launch_ABCD1234'));
      expect(keys, contains('disconnect_192.168.1.100:5555'));
      expect(keys, contains('disconnect_ABCD1234'));
      expect(keys, contains('pair'));
      expect(keys, contains('refresh'));
      expect(keys, contains('settings'));
      expect(keys, contains('quit'));
    });

    test('scrcpy config produces valid args', () {
      const config = ScrcpyConfig(
        maxSize: 1280,
        videoBitRate: '4M',
        videoCodec: 'h265',
      );
      final args = config.toArgs('Pixel7');

      expect(args.first, '--serial');
      expect(args[1], 'Pixel7');
      expect(args, contains('--max-size'));
      expect(args, contains('1280'));
    });

    test('settings round-trip preserves all fields', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'scrcpy_plus_integ_',
      );
      try {
        final manager = SettingsManager(configDir: tempDir.path);
        const config = ScrcpyConfig(
          scrcpyPath: '/opt/homebrew/bin/scrcpy',
          maxSize: 1920,
          videoBitRate: '12M',
          videoCodec: 'h265',
        );

        await manager.saveConfig(config);
        await manager.saveKnownSerials(['dev1', 'dev2', 'dev3']);

        final loaded = await manager.loadConfig();
        final serials = await manager.loadKnownSerials();

        expect(loaded.scrcpyPath, '/opt/homebrew/bin/scrcpy');
        expect(loaded.maxSize, 1920);
        expect(loaded.videoBitRate, '12M');
        expect(loaded.videoCodec, 'h265');
        expect(serials, ['dev1', 'dev2', 'dev3']);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
