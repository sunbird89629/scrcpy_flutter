import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import '../agent_eval_case.dart';

final youtubeHistoryRecentCase = AgentEvalCase(
  id: 'youtube_history_recent',
  description:
      'Navigate to YouTube history and summarize recent visible videos.',
  task: '''
打开 YouTube 应用，进入观看历史记录页面，读取当前屏幕可见的最近视频条目。

具体步骤：
1. 如果当前不在 YouTube 首页，按 Home 回到桌面后重新 Launch YouTube。
2. 在 YouTube 首页，点击底部导航栏最右边的"我"标签（不是搜索图标，不是首页，是"我"），进入个人中心。
3. 在个人中心页面中找到"历史记录"或"观看记录"入口，点击进入。
4. 在历史记录列表中，读取当前屏幕可见的最近 2~3 个视频条目（标题或频道名）。
5. 不要点击视频条目——只看不点，避免进入播放页。
6. 如果遇到广告弹窗，按 Back 关闭；如果 Back 无效按 Home 回到桌面重新开始。

完成后用 finish(message="总结内容") 返回。
''',
  config: AgentConfig(maxSteps: 30, repeatedActionThreshold: 8),
  setup: (device) async {
    await device.enableShowTouches();
    // Force-stop and relaunch to ensure clean homepage state
    await device.adb.shell([
      'am',
      'force-stop',
      'com.google.android.youtube',
    ], deviceId: device.deviceId);
    await device.adb.shell([
      'am',
      'force-stop',
      'com.android.chrome',
    ], deviceId: device.deviceId);
    await device.adb.shell([
      'am',
      'start',
      '-n',
      'com.google.android.youtube/com.google.android.apps.youtube.app.WatchWhileActivity',
    ], deviceId: device.deviceId);
    await device.waitFor(const Duration(seconds: 3));
  },
  teardown: (device) => device.disableShowTouches(),
  assertions: [
    TextContainsAssertion('视频'),
    VisualContainsAssertion('YouTube 历史记录页面'),
  ],
);
