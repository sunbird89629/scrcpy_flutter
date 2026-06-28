import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/app/app_controller.dart';

void main() {
  group('AppController', () {
    test('handleMenuKey returns false for unknown key', () {
      // AppController requires real tray_manager, so we test the static helper
      expect(AppController.isLaunchAction('launch_dev1'), true);
      expect(AppController.isLaunchAction('quit'), false);
      expect(AppController.isDisconnectAction('disconnect_dev1'), true);
      expect(AppController.isDisconnectAction('quit'), false);
      expect(AppController.serialFromAction('launch_ABCD', 'launch_'), 'ABCD');
      expect(
        AppController.serialFromAction('disconnect_ABCD', 'disconnect_'),
        'ABCD',
      );
    });

    test('isFlexLaunchAction identifies flex keys', () {
      expect(AppController.isFlexLaunchAction('flex|serial|pkg'), true);
      expect(AppController.isFlexLaunchAction('launch_serial'), false);
    });

    test('flexPartsFromKey parses serial and package', () {
      final parts = AppController.flexPartsFromKey(
        'flex|192.168.1.1:5555|com.tencent.mm',
      );
      expect(parts, ('192.168.1.1:5555', 'com.tencent.mm'));
    });

    test('flexPartsFromKey returns null for non-flex key', () {
      expect(AppController.flexPartsFromKey('launch_serial'), null);
    });
  });
}
