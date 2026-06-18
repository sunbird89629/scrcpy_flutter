@Tags(['real-device'])
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

final _log = Logger('youtube');

// Reusable task: collect today's YouTube watch history into a table.
// The agent records each entry in its reasoning (Note) and returns the table in
// finish(message=...). The agent's system prompt injects today's date via
// {DATE}, so "今天" resolves at runtime.
const _task = '''
在 YouTube 应用中查看我今天的观看历史，并整理成表格。具体步骤如下：

1. 如果当前不在 YouTube，先 Launch 打开 YouTube 应用。
2. 进入观看历史页面：点击右下角的头像/「你」(You) 标签，进入个人页后找到「观看记录 / History」，点击「查看全部 / View all」进入完整历史列表。
3. 历史记录按日期分组（今天、昨天、具体日期）。每滑动到新的一屏，先在 think 中把当前屏可见的每条记录列出来（视频标题、频道名称、观看日期或所在日期分组），再继续。
4. 通过 Swipe 向上滑动加载更多记录。满足以下任一条件就停止滑动：出现早于 今天 的记录；或者已经累计滑动 8 次。早于 今天 的记录不要计入。
5. 停止滑动后，立即把已看到的、属于 今天 的记录整理成表格，通过 finish 返回（不要继续滑动）。表格包含以下列：
   | 序号 | 视频标题 | 频道 | 观看日期 |
   按时间从近到远排列。如果一条记录都没收集到，也用 finish 说明原因。

注意：
- ⚠️ 绝对不要点击历史列表里的任何视频条目——点击会直接开始播放视频，导致偏离任务。只用 Swipe 滚动浏览，用眼睛读取并在 think 中记录文字信息，全程不要 Tap 列表中的视频。
- 如果不小心进入了视频播放页或 Shorts 页，立即用 Back 返回，必要时点击左上角返回箭头回到历史列表。
- 如果 YouTube 未登录或历史记录功能被关闭，无法获取历史，请用 Take_over 请求人工协助或在 finish 中说明原因。
- 如果某条记录看不清观看日期，用其所在的日期分组标题作为观看日期。
- 如果截图全黑或提示敏感屏幕，先 Wait 一次再重试，不要把黑屏当作真实页面。
''';

void main() {
  initLogging();
  test(
    'e2e: collect YouTube watch history into a table',
    timeout: const Timeout(Duration(minutes: 12)),
    () async {
      final adbClient = AdbClient();
      final devices = await adbClient.getDevices();
      if (devices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }
      final targetDevice = devices.first;

      final (screenWidth, screenHeight) = await adbClient.getDeviceScreenInfo(
        targetDevice,
      );
      final runner = AdbActionRunner(
        adb: ScrcpyMcpAdb(adbClient),
        deviceId: targetDevice,
        size: (screenWidth.toInt(), screenHeight.toInt()),
      );
      final agent = PhoneAgent(
        config: AgentConfig(),
        client: AutoGLMOfficialClient.fromTest(),
        takeScreenshot: blankRetryingScreenshot(
          () => adbClient.takeScreenshot(targetDevice),
        ),
        actionRunner: runner.run,
      );
      final result = await agent.run(_task);
      _log.info(
        'YouTube history result (steps=${result.steps}, '
        'success=${result.success}):\n${result.result}',
      );
      // The agent must return a non-empty summary (the table, or a reason it
      // could not be produced). Content is inspected from the logged result.
      expect(result.result, isNotEmpty);
    },
  );
}
