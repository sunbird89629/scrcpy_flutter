@Tags(['real-device'])
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/app_logger.dart';
import 'package:test/test.dart';

void main() {
  initLogging();
  final client = AdbClient();

  late String firstDevice;

  setUpAll(() async {
    final devices = await client.getDevices();
    firstDevice = devices.first;
  });

  test('getDevices returns device list', () async {
    final devices = await client.getDevices();
    expect(devices, isNotEmpty);
  });

  test('getDeviceInfo returns info for first device', () async {
    expect(firstDevice, isNotEmpty, reason: 'Requires a connected ADB device');
    final info = await client.getDeviceInfo(firstDevice);
    expect(info.serial, firstDevice);
    expect(info.model, isNotNull);
  });

  test('getDeviceScreenInfo returns screen info for first device', () async {
    final screenInfo = await client.getDeviceScreenInfo(firstDevice);
    expect(screenInfo, isNotNull);
  });
}
