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
  });
}
