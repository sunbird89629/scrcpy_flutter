import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

/// Dummy screenshot — a minimal 1x1 PNG.
Future<({String base64, String mimeType})> _fakeScreenshot() async => (
  base64:
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  mimeType: 'image/png',
);

void main() {
  test('real phone agent model test', () async {
    initLogging();
    final phoneAgent = PhoneAgent(
      config: const AgentConfig(maxSteps: 5),
      llmClient: OpenAiLlmClient.fromTest(),
      takeScreenshot: _fakeScreenshot,
      actionRunner: (action) async => 'executed: $action',
    );
    final agentResult = await phoneAgent.run('获取当前的屏幕内容');
    expect(agentResult, isNotNull);
  });
}
