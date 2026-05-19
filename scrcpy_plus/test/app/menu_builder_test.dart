import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_plus/app/menu_builder.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

void main() {
  group('MenuBuilder', () {
    test('buildMenu returns quit item', () {
      final menu = MenuBuilder.buildMenu(devices: []);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, contains('quit'));
    });

    test('buildMenu returns pair item when no devices', () {
      final menu = MenuBuilder.buildMenu(devices: []);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, contains('pair'));
    });

    test('buildMenu includes device items', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: 'ABCD1234',
          status: DeviceStatus.online,
          model: 'Pixel 7',
        ),
      );
      final menu = MenuBuilder.buildMenu(devices: [entry]);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, contains('launch_ABCD1234'));
    });

    test('buildMenu includes refresh item', () {
      final menu = MenuBuilder.buildMenu(devices: []);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, contains('refresh'));
    });
  });
}
