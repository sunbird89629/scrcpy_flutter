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

    test('buildMenu shows mcp url and copy item when running', () {
      final menu = MenuBuilder.buildMenu(
        devices: [],
        mcpUrl: 'http://localhost:7070/mcp',
      );
      final copyItem = menu.items!.firstWhere(
        (i) => i.key == MenuBuilder.copyMcpKey,
      );
      expect(copyItem.label, contains('http://localhost:7070/mcp'));
    });

    test('buildMenu shows mcp error line when error present', () {
      final menu = MenuBuilder.buildMenu(devices: [], mcpError: 'port in use');
      final labels = menu.items!.map((i) => i.label).toList();
      expect(labels.any((l) => l != null && l.contains('port in use')), true);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, isNot(contains(MenuBuilder.copyMcpKey)));
    });

    test('buildMenu omits mcp section when no url and no error', () {
      final menu = MenuBuilder.buildMenu(devices: []);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, isNot(contains(MenuBuilder.copyMcpKey)));
    });

    test('buildMenu shows flex submenu when device has packages', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(serial: 'ABCD1234', status: DeviceStatus.online),
        packages: ['com.tencent.mm', 'org.mozilla.firefox'],
      );
      final menu = MenuBuilder.buildMenu(devices: [entry]);
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
      final menu = MenuBuilder.buildMenu(devices: [entry]);
      final hasSubmenu = menu.items!.any((i) => i.submenu != null);
      expect(hasSubmenu, false);
    });
  });
}
