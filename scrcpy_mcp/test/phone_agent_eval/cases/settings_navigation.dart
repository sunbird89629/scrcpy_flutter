import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import '../agent_eval_case.dart';

const settingsNavigationCase = AgentEvalCase(
  id: 'settings_navigation',
  description: 'Open Android Settings and verify the settings UI is visible.',
  task: '''
请打开 Android 系统设置页面。完成后用 finish(message="done") 返回。
''',
  config: AgentConfig(maxSteps: 10),
  assertions: [VisualContainsAssertion('Android 系统设置页面')],
);
