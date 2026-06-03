@Tags(['real-device'])
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'adb_agent_runner.dart';

final _log = Logger('youtube.history');

// Reusable task: collect the last week's YouTube watch history into a table.
// The agent records each entry in its reasoning (Note) and returns the table in
// finish(message=...). NB: the date range is relative — update it before a run,
// or rely on the agent's injected {DATE} for "最近一周".
const _task = '''
在 YouTube 应用中查看我最近一周（2026年5月27日 至 2026年6月3日）的观看历史，并整理成表格。具体步骤如下：

1. 如果当前不在 YouTube，先 Launch 打开 YouTube 应用。
2. 进入观看历史页面：点击右下角的头像/「你」(You) 标签，进入个人页后找到「观看记录 / History」，点击「查看全部 / View all」进入完整历史列表。
3. 历史记录按日期分组（今天、昨天、具体日期）。从最上方开始逐条查看，用 Note 记录每条记录的：视频标题、频道名称、观看日期（或所在日期分组）。
4. 通过 Swipe 向上滑动加载更多记录，继续记录，直到出现早于 2026年5月27日 的记录为止；早于这个日期的记录不要记录。
5. 全部收集完成后，把结果整理成一个表格，通过 finish 返回，表格包含以下列：
   | 序号 | 视频标题 | 频道 | 观看日期 |
   只统计 2026-05-27 至 2026-06-03 之间的记录，按时间从近到远排列。

注意：
- 如果 YouTube 未登录或历史记录功能被关闭，无法获取历史，请用 Take_over 请求人工协助或在 finish 中说明原因。
- 如果某条记录看不清观看日期，用其所在的日期分组标题作为观看日期。
''';

void main() {
  test(
    'e2e: collect YouTube watch history into a table',
    () async {
      initLogging();
      final adb = ScrcpyMcpAdb(AdbClient());
      if ((await adb.getDevices()).isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final result = await runAgentTask(
        adb: adb,
        task: _task,
        // History tasks need many scroll + record steps.
        maxSteps: 25,
      );

      _log.info(
        'YouTube history result (steps=${result.steps}, '
        'success=${result.success}):\n${result.result}',
      );
      // The agent must return a non-empty summary (the table, or a reason it
      // could not be produced). Content is inspected from the logged result.
      expect(result.result, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
