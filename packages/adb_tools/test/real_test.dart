import 'package:adb_tools/adb_tools.dart';
import 'package:autoglm_logger/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test real get device list', () async {
    initLogging();
    final client = AdbClientImpl();
    final devices = await client.getDevicesWithInfo();
    expect(devices, isNotEmpty);
  });
}
