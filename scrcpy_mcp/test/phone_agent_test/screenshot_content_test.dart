@Tags(['real-device'])
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'utils/visual_assertion.dart';

const _deviceId = '39111FDJH00D47';

void main() {
  test(
    'screenshot contains app icons',
    () async {
      initLogging();
      final adb = ScrcpyMcpAdb(AdbClient());
      final client = AutoglmLlmClient.fromTest();

      final r = await checkDeviceScreenContains(
        client: client,
        adb: adb,
        deviceId: _deviceId,
        expectation: '应用图标',
      );

      expect(r.matched, isTrue, reason: r.reason);
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: false,
  );

  test(
    'screenshot does not contain a calculator app',
    () async {
      initLogging();
      final adb = ScrcpyMcpAdb(AdbClient());
      final client = AutoglmLlmClient.fromTest();

      // Desktop should not contain a calculator app specifically.
      final r = await checkDeviceScreenContains(
        client: client,
        adb: adb,
        deviceId: _deviceId,
        expectation: '计算器',
      );

      expect(r.matched, isFalse, reason: r.reason);
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: false,
  );
}
