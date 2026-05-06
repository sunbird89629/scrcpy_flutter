import 'package:adb_tools/adb_tools.dart';
import 'package:autoglm_logger/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  initLogging();
  final client = AdbClientImpl();

  test('getDevices returns device list', () async {
    final devices = await client.getDevices();
    expect(devices, isNotEmpty);
  });

  test('getDeviceInfo returns info for first device', () async {
    final devices = await client.getDevices();
    expect(devices, isNotEmpty, reason: 'Requires a connected ADB device');
    final info = await client.getDeviceInfo(devices.first);
    expect(info.serial, devices.first);
    expect(info.model, isNotNull);
  });
}
