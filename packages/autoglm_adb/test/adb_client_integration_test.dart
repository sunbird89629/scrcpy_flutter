import 'package:autoglm_adb/src/adb_client.dart';
import 'package:autoglm_adb/src/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdbClient Integration Tests', () {
    late AdbClient client;

    setUpAll(() {
      client = const AdbClientImpl();
    });

    test(
      'getVersion returns adb version',
      () async {
        try {
          final version = await client.getVersion();
          expect(version, isNotEmpty);
          expect(version.toLowerCase(), contains('android debug bridge'));
        } on AdbException catch (e) {
          fail('ADB should be available: $e');
        }
      },
      skip: true,
    );

    test(
      'devices returns list of connected devices',
      () async {
        try {
          final devices = await client.getDevices();
          expect(devices, isA<List<String>>());
          // 可能没有连接的设备，但命令应该成功执行
        } on AdbException catch (e) {
          fail('ADB should be available: $e');
        }
      },
      skip: true,
    );

    test('getVersion fails with wrong adb path', () async {
      const badClient = AdbClientImpl(adbPath: '/nonexistent/adb');

      expect(() => badClient.getVersion(), throwsA(isA<AdbException>()));
    });

    test(
      'devices command parses output correctly with real adb',
      () async {
        try {
          final devices = await client.getDevices();
          // 验证返回值是字符串列表
          expect(devices, isA<List<String>>());
          // 如果有设备，应该是 "ip:port" 或 "device-id" 格式
          for (final device in devices) {
            expect(device, isNotEmpty);
            expect(device, isA<String>());
          }
        } on AdbException catch (e) {
          fail('ADB should be available: $e');
        }
      },
      skip: true,
    );
  });
}
