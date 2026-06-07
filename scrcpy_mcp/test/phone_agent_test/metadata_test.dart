@Tags(['real-device'])
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'utils/adb_agent_runner.dart';
import 'utils/visual_assertion.dart';

const _task = '''
请顺序执行如下四个操作：
1. 点击屏幕的左上角
2. 点击屏幕的右上角
3. 点击屏幕的右下角
4. 点击屏幕的左下角
操作完成后返回 done
''';

final _logger = Logger('metadata_test');

void main() {
  initLogging();
  test(
    'e2e: test device and model metedata',
    () async {
      initLogging();
      final adbClient = AdbClient();
      final adb = ScrcpyMcpAdb(adbClient);
      final devices = await adb.getDevices();
      if (devices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }
      final deviceId = devices.first;

      final deviceInfo = await adbClient.getDeviceInfo(deviceId);
      _logger.info('deviceInfo.screenWidth:${deviceInfo.screenWidth}');
      _logger.info('deviceInfo.screenHeight:${deviceInfo.screenHeight}');
      final result = await runAgentTask(
        adb: adbClient,
        deviceId: deviceId,
        task: _task,
        maxSteps: 10,
      );
      expect(result, isNotNull);

      // Verify the agent actually reached the Twitter homepage.
      final check = await checkDeviceScreenContains(
        client: AutoglmLlmClient.fromTest(),
        adb: adb,
        deviceId: deviceId,
        expectation: 'Twitter（X）的主页',
      );
      expect(check.matched, isTrue, reason: check.reason);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
