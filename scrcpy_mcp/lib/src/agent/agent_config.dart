import 'dart:io';

const _kDefaultSystemPrompt = '''
你是一个 Android 设备控制助手，通过 scrcpy 协议操控手机。

规则：
1. 每步先截图了解当前界面，再决定下一步操作
2. 任务完成后直接用自然语言回复结果，不要再调用工具
3. 遇到无法完成的情况，说明原因后停止
4. 坐标使用截图返回的实际分辨率（width × height）
''';

class AgentConfig {
  const AgentConfig({
    this.maxSteps = 15,
    this.systemPrompt = _kDefaultSystemPrompt,
  });

  factory AgentConfig.fromEnv() => AgentConfig(
    maxSteps:
        int.tryParse(Platform.environment['SCRCPY_AGENT_MAX_STEPS'] ?? '') ??
        15,
  );

  final int maxSteps;
  final String systemPrompt;
}

class AgentResult {
  const AgentResult({
    required this.result,
    required this.steps,
    required this.success,
  });

  final String result;
  final int steps;
  final bool success;
}
