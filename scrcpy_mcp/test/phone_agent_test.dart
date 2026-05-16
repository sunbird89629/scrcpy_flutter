import 'package:scrcpy_mcp/src/agent/agent_config.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:scrcpy_mcp/src/agent/phone_agent.dart';
import 'package:test/test.dart';

// Fake that replays a fixed sequence of LlmResponse values.
class _FakeLlmClient implements LlmClient {
  _FakeLlmClient(this._responses);
  final List<LlmResponse> _responses;
  int _i = 0;

  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required List<ToolSchema> tools,
  }) async =>
      _responses[_i++];
}

void main() {
  group('PhoneAgent', () {
    PhoneAgent makeAgent(
      List<LlmResponse> responses, {
      ToolExecutor? executor,
      int maxSteps = 10,
    }) =>
        PhoneAgent(
          config: AgentConfig(maxSteps: maxSteps),
          llmClient: _FakeLlmClient(responses),
          tools: const [],
          executeToolCall: executor ??
              (_, __) async =>
                  (text: 'ok', imageBase64: null, imageMimeType: null),
        );

    test('returns success when LLM stops without tool calls', () async {
      final result = await makeAgent([
        const LlmResponse(text: 'Task complete'),
      ]).run('open settings');

      expect(result.success, isTrue);
      expect(result.result, 'Task complete');
      expect(result.steps, 1);
    });

    test('executes tool calls before receiving final answer', () async {
      final executed = <String>[];
      final result = await makeAgent(
        [
          LlmResponse(toolCalls: [
            const ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
          ]),
          const LlmResponse(text: 'Done'),
        ],
        executor: (name, _) async {
          executed.add(name);
          return (
            text: 'screenshot taken',
            imageBase64: null,
            imageMimeType: null
          );
        },
      ).run('check screen');

      expect(result.success, isTrue);
      expect(executed, ['take_screenshot']);
      expect(result.steps, 2);
    });

    test('feeds tool result back into message history', () async {
      final capturingFake = _CapturingLlmClient([
        LlmResponse(toolCalls: [
          const ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
        ]),
        const LlmResponse(text: 'Done'),
      ]);

      final capturingAgent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        llmClient: capturingFake,
        tools: const [],
        executeToolCall: (_, __) async =>
            (text: 'res: 1264x2800', imageBase64: null, imageMimeType: null),
      );

      await capturingAgent.run('check screen');

      // Second call should include tool result in history
      final secondCallMessages = capturingFake.capturedMessages[1];
      expect(secondCallMessages.any((m) => m.role == 'tool'), isTrue);
      final toolMsg = secondCallMessages.firstWhere((m) => m.role == 'tool');
      expect(toolMsg.textContent, 'res: 1264x2800');
      expect(toolMsg.toolCallId, 'c1');
    });

    test('returns failure when max steps reached', () async {
      final result = await makeAgent(
        List.generate(
          3,
          (_) => LlmResponse(toolCalls: [
            const ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
          ]),
        ),
        maxSteps: 3,
      ).run('impossible task');

      expect(result.success, isFalse);
      expect(result.steps, 3);
      expect(result.result, contains('Max steps'));
    });

    test('continues loop when tool execution throws', () async {
      final result = await makeAgent(
        [
          LlmResponse(toolCalls: [
            const ToolCall(id: 'c1', name: 'bad_tool', arguments: '{}'),
          ]),
          const LlmResponse(text: 'Recovered after error'),
        ],
        executor: (_, __) async => throw Exception('network fail'),
      ).run('test recovery');

      expect(result.success, isTrue);
      expect(result.result, 'Recovered after error');
    });

    test('includes image in tool result message when executor returns one',
        () async {
      final capturingFake = _CapturingLlmClient([
        LlmResponse(toolCalls: [
          const ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
        ]),
        const LlmResponse(text: 'Done'),
      ]);

      await PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        llmClient: capturingFake,
        tools: const [],
        executeToolCall: (_, __) async => (
          text: 'res: 1264x2800',
          imageBase64: 'base64png',
          imageMimeType: 'image/png',
        ),
      ).run('screenshot test');

      final toolMsg =
          capturingFake.capturedMessages[1].firstWhere((m) => m.role == 'tool');
      expect(toolMsg.imageBase64, 'base64png');
      expect(toolMsg.imageMimeType, 'image/png');
    });
  });
}

class _CapturingLlmClient implements LlmClient {
  _CapturingLlmClient(this._responses);
  final List<LlmResponse> _responses;
  final capturedMessages = <List<LlmMessage>>[];
  int _i = 0;

  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required List<ToolSchema> tools,
  }) async {
    capturedMessages.add(List.from(messages));
    return _responses[_i++];
  }
}
