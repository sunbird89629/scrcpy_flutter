@Tags(['real-device'])
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/app_logger.dart';
import 'package:test/test.dart';

void main() {
  test('test real get device list', () async {
    initLogging();
    final client = AdbClient();
    final devices = await client.getDevices();
    expect(devices, isNotEmpty);
  });
}
