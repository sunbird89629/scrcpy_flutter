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
2. 在 YouTube 首页，点击底部导航栏最右边的"我"标签，进入个人中心。
3. 在个人中心页面中，找到"历史记录"区域（通常在页面上半部分）。不要点击视频缩略图——那些是视频，点击会播放。要找文字链接"查看全部"或"历史记录"标题旁边的箭头图标，点那个进入完整历史列表。如果页面上有视频缩略图，绝对不要碰它们。
4. 进入完整历史记录列表后，读取当前屏幕可见的最近 2~3 个视频条目（标题或频道名）。只看不点。
5. 如果不小心进入了视频播放页，按 Back 返回；如果 Back 无效，连续按 Back 3 次然后重新走步骤 1-3。

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
