import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('real phone agent model test', () async {
    initLogging();
    final phoneAgent = PhoneAgent(
      config: const AgentConfig(maxSteps: 5),
      llmClient: OpenAiLlmClient.fromTest(),
      tools: const [],
      executeToolCall: (_, __) async => (
        text: 'res: 1264x2800',
        imageBase64: 'base64png',
        imageMimeType: 'image/png',
      ),
    );
    final agentResult = await phoneAgent.run('获取当前的屏幕内容');
    expect(agentResult, isNotNull);
  });
}
