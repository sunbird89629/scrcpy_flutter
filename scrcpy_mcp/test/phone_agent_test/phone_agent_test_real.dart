@Tags(['real-device'])
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'utils/adb_agent_runner.dart';
import 'utils/visual_assertion.dart';

const _task = '''
  帮我通过 chrome 打开 twitter 的官网,具体步骤如下：
  1. 如果当前不在 **HOME** 页面，先通过 HOME 键进入  HOME 页面
  2. 打开chrome
  3. 在地址栏输入 twitter 的网址：https://www.x.com
  4. 点击输入法上的确认按钮
  5. 等待页面加载
  6. 确认当前页面是 twitter 的主页
''';

void main() {
  test('e2e: open twitter with chrome', () async {
    initLogging();
    final adbClient = AdbClient();
    final adb = ScrcpyMcpAdb(adbClient);
    final devices = await adb.getDevices();
    if (devices.isEmpty) {
      markTestSkipped('No Android device connected via ADB');
      return;
    }
    final deviceId = devices.first;

    final result = await runAgentTask(
      adb: adbClient,
      deviceId: deviceId,
      task: _task,
      maxSteps: 10,
    );
    expect(result, isNotNull);

    // Verify the agent actually reached the Twitter homepage.
    final check = await checkDeviceScreenContains(
      chat: AutoGLMClient.fromTest().chat,
      adb: adb,
      deviceId: deviceId,
      expectation: 'Twitter（X）的主页',
    );
    expect(check.matched, isTrue, reason: check.reason);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
