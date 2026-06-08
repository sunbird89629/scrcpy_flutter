import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import '../agent_eval_case.dart';

const youtubeHistoryRecentCase = AgentEvalCase(
  id: 'youtube_history_recent',
  description:
      'Navigate to YouTube history and summarize recent visible videos.',
  task: '''
打开 YouTube 的历史记录页面，读取当前屏幕可见的最近视频条目。
不要点击视频条目，避免进入播放页。只需要总结当前可见的 2 到 3 个视频标题或频道信息。
完成后用 finish(message="...") 返回总结。
''',
  config: AgentConfig(maxSteps: 25, repeatedActionThreshold: 8),
  assertions: [
    TextContainsAssertion('视频'),
    VisualContainsAssertion('YouTube 历史记录页面'),
  ],
);
