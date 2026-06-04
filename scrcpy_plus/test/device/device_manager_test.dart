import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/device/device_manager.dart';

void main() {
  group('DeviceManager', () {
    test('devices list is initially empty', () {
      final manager = DeviceManager();
      expect(manager.devices, isEmpty);
    });

    test('notifyListeners fires on change', () {
      final manager = DeviceManager();
      var notified = false;
      manager.addListener(() => notified = true);
      manager.setDevices([]);
      expect(notified, true);
    });

    test('hasConnected reflects device list state', () {
      final manager = DeviceManager();
      expect(manager.hasConnected, false);
    });
  });
}
