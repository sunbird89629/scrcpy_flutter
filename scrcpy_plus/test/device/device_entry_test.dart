import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

void main() {
  group('DeviceEntry', () {
    test('isWifi detects IP:port serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: '192.168.1.100:5555',
          status: DeviceStatus.online,
        ),
      );
      expect(entry.isWifi, true);
    });

    test('isWifi returns false for USB serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(serial: 'ABCD1234', status: DeviceStatus.online),
      );
      expect(entry.isWifi, false);
    });

    test('displayName uses model when available', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: 'ABCD1234',
          status: DeviceStatus.online,
          model: 'Pixel 7',
        ),
      );
      expect(entry.displayName, 'Pixel 7');
    });

    test('displayName falls back to serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(serial: 'ABCD1234', status: DeviceStatus.online),
      );
      expect(entry.displayName, 'ABCD1234');
    });

    test('connectionLabel shows WiFi for IP serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: '192.168.1.100:5555',
          status: DeviceStatus.online,
        ),
      );
      expect(entry.connectionLabel, 'WiFi');
    });

    test('connectionLabel shows USB for non-IP serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(serial: 'ABCD1234', status: DeviceStatus.online),
      );
      expect(entry.connectionLabel, 'USB');
    });

    test('menuLabel combines displayName and connectionLabel', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: '192.168.1.100:5555',
          status: DeviceStatus.online,
          model: 'Pixel 7',
        ),
      );
      expect(entry.menuLabel, 'Pixel 7 (WiFi)');
    });

    test('detailLine includes battery when available', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: 'ABCD1234',
          status: DeviceStatus.online,
          androidVersion: '14',
          screenWidth: 1080,
          screenHeight: 2400,
        ),
        battery: 85,
      );
      expect(entry.detailLine, 'Battery: 85% | Android 14 | 1080x2400');
    });

    test('detailLine returns null when no details available', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(serial: 'ABCD1234', status: DeviceStatus.online),
      );
      expect(entry.detailLine, isNull);
    });
  });
}
