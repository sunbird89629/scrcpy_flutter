import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import '../agent_eval_case.dart';

const twitterHomeCase = AgentEvalCase(
  id: 'twitter_home',
  description:
      'Open Twitter/X homepage through Chrome and verify it is visible.',
  task: '''
帮我通过 Chrome 打开 Twitter/X 官网，网址是 https://www.x.com。
如果不在主页，先按 HOME。打开后等待页面加载，并确认当前页面是 Twitter/X 主页。
完成后用 finish(message="done") 返回。
''',
  config: AgentConfig(maxSteps: 12),
  assertions: [VisualContainsAssertion('Twitter（X）的主页')],
);
