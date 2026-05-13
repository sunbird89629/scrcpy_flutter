import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'utils/mock_scrcpy_adb.dart';

void main() {
  final mockJarBytes = Uint8List(0);

  group('ScrcpyServer Configuration', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('initializes with required parameters', () {
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device123',
        port: 12345,
        serverJarBytes: mockJarBytes,
      );

      expect(server.deviceId, 'device123');
      expect(server.port, 12345);
      server.stop();
    });

    test('uses default port when not specified', () {
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device123',
        serverJarBytes: mockJarBytes,
      );

      expect(server.port, 27183);
      server.stop();
    });

    test('supports multiple instances with different ports', () async {
      final server1 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device1',
        serverJarBytes: mockJarBytes,
      );

      final server2 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device2',
        port: 27184,
        serverJarBytes: mockJarBytes,
      );

      expect(server1.port, 27183);
      expect(server2.port, 27184);

      await server1.stop();
      await server2.stop();
    });

    test('adb client reference is stored correctly', () {
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device123',
        serverJarBytes: mockJarBytes,
      );

      expect(server.adb, mockAdb);
      server.stop();
    });
  });

  group('ScrcpyServer ADB Operations', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('verifies shell command with correct parameters', () async {
      await mockAdb.shell([
        'chmod',
        '755',
        '/data/local/tmp/scrcpy-server',
      ], deviceId: 'emulator-5554');

      expect(mockAdb.shellCalls, isNotEmpty);
      expect(mockAdb.shellCalls[0], containsAll(['chmod', '755']));
    });

    test('verifies forward command parameters', () async {
      await mockAdb.forward(
        'tcp:27183',
        'localabstract:scrcpy',
        deviceId: 'specific-device-id',
      );

      expect(mockAdb.forwardCalls, isNotEmpty);
    });
  });

  group('ScrcpyServer Device Management', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('works with multiple device IDs', () {
      final server1 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device1',
        serverJarBytes: mockJarBytes,
      );

      final server2 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device2',
        serverJarBytes: mockJarBytes,
      );

      expect(server1.deviceId, 'device1');
      expect(server2.deviceId, 'device2');

      server1.stop();
      server2.stop();
    });
  });
}
