import 'package:adb_tools/adb_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/app/menu_builder.dart';
import 'package:scrcpy_plus/device/device_entry.dart';
import 'package:scrcpy_plus/device/device_group.dart';

DeviceGroup _group(DeviceEntry entry) => DeviceGroup(
  physicalSerial: entry.info.physicalSerial,
  displayName: entry.displayName,
  connections: [entry],
);

void main() {
  group('MenuBuilder', () {
    test('buildMenu returns quit item', () {
      final menu = MenuBuilder.buildMenu(groups: []);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, contains('quit'));
    });

    test('buildMenu returns pair item when no devices', () {
      final menu = MenuBuilder.buildMenu(groups: []);
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
      final menu = MenuBuilder.buildMenu(groups: [_group(entry)]);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, contains('launch_ABCD1234'));
    });

    test('buildMenu includes refresh item', () {
      final menu = MenuBuilder.buildMenu(groups: []);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, contains('refresh'));
    });

    test('buildMenu shows mcp url and copy item when running', () {
      final menu = MenuBuilder.buildMenu(
        groups: [],
        mcpUrl: 'http://localhost:7070/mcp',
      );
      final copyItem = menu.items!.firstWhere(
        (i) => i.key == MenuBuilder.copyMcpKey,
      );
      expect(copyItem.label, contains('http://localhost:7070/mcp'));
    });

    test('buildMenu shows mcp error line when error present', () {
      final menu = MenuBuilder.buildMenu(groups: [], mcpError: 'port in use');
      final labels = menu.items!.map((i) => i.label).toList();
      expect(labels.any((l) => l != null && l.contains('port in use')), true);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, isNot(contains(MenuBuilder.copyMcpKey)));
    });

    test('buildMenu omits mcp section when no url and no error', () {
      final menu = MenuBuilder.buildMenu(groups: []);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, isNot(contains(MenuBuilder.copyMcpKey)));
    });

    test('buildMenu shows flex submenu when device has packages', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(serial: 'ABCD1234', status: DeviceStatus.online),
        packages: ['com.tencent.mm', 'org.mozilla.firefox'],
      );
      final menu = MenuBuilder.buildMenu(groups: [_group(entry)]);
      final submenuItem = menu.items!.firstWhere(
        (i) => i.submenu != null,
        orElse: () => throw TestFailure('no submenu found'),
      );
      final subKeys = submenuItem.submenu!.items!.map((i) => i.key).toList();
      expect(subKeys, contains('flex|ABCD1234|com.tencent.mm'));
      expect(subKeys, contains('flex|ABCD1234|org.mozilla.firefox'));
    });

    test('buildMenu omits flex submenu when device has no packages', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(serial: 'ABCD1234', status: DeviceStatus.online),
      );
      final menu = MenuBuilder.buildMenu(groups: [_group(entry)]);
      final hasSubmenu = menu.items!.any((i) => i.submenu != null);
      expect(hasSubmenu, false);
    });

    test('single group with two connections shows connection labels', () {
      final usb = DeviceEntry(
        info: const DeviceInfo(serial: 'ABCD1234', status: DeviceStatus.online),
      );
      final wireless = DeviceEntry(
        info: const DeviceInfo(
          serial: 'adb-ABCD1234-xXxXxX._adb-tls-connect._tcp',
          status: DeviceStatus.online,
        ),
      );
      final group = DeviceGroup(
        physicalSerial: 'ABCD1234',
        displayName: 'Pixel 7',
        connections: [usb, wireless],
      );
      final menu = MenuBuilder.buildMenu(groups: [group]);
      final labels = menu.items!
          .where((i) => i.label != null)
          .map((i) => i.label!)
          .toList();
      expect(labels.any((l) => l.contains('· USB')), true);
      expect(labels.any((l) => l.contains('· Wireless')), true);
    });
  });
}
