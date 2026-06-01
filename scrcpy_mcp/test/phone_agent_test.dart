import 'package:scrcpy_mcp/scrcpy_mcp.dart';
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
  }) async => _responses[_i++];
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

/// Subset of real MCP tool schemas that the agent can call.
/// Mirrors the schemas defined in lib/src/tools/ so the LLM receives accurate
/// tool definitions during testing.
const _agentTools = [
  ToolSchema(
    name: 'list_devices',
    description: 'List connected Android devices',
    parameters: {},
  ),
  ToolSchema(
    name: 'start_mirroring',
    description: 'Start screen mirroring on a device',
    parameters: {
      'type': 'object',
      'properties': {
        'device_id': {
          'type': 'string',
          'description': 'The Android device serial',
        },
      },
      'required': ['device_id'],
    },
  ),
  ToolSchema(
    name: 'take_screenshot',
    description: 'Take a screenshot of the device screen',
    parameters: {
      'type': 'object',
      'properties': {
        'device_id': {
          'type': 'string',
          'description':
              'Device serial (optional, uses connected device if omitted)',
        },
      },
    },
  ),
  ToolSchema(
    name: 'inject_touch',
    description: 'Inject a touch event (tap/swipe segment)',
    parameters: {
      'type': 'object',
      'properties': {
        'x': {'type': 'integer', 'description': 'X coordinate'},
        'y': {'type': 'integer', 'description': 'Y coordinate'},
        'width': {'type': 'integer', 'description': 'Screen width'},
        'height': {'type': 'integer', 'description': 'Screen height'},
        'action': {
          'type': 'integer',
          'description': 'Touch action: 0=down, 1=up, 2=move (default: 0)',
        },
      },
      'required': ['x', 'y', 'width', 'height'],
    },
  ),
  ToolSchema(
    name: 'inject_swipe',
    description: 'Swipe between two points',
    parameters: {
      'type': 'object',
      'properties': {
        'x1': {'type': 'integer', 'description': 'Start X coordinate'},
        'y1': {'type': 'integer', 'description': 'Start Y coordinate'},
        'x2': {'type': 'integer', 'description': 'End X coordinate'},
        'y2': {'type': 'integer', 'description': 'End Y coordinate'},
        'width': {'type': 'integer', 'description': 'Screen width'},
        'height': {'type': 'integer', 'description': 'Screen height'},
        'durationMs': {
          'type': 'integer',
          'description':
              'Total swipe duration in ms (default 300). Shorter = fling.',
        },
      },
      'required': ['x1', 'y1', 'x2', 'y2', 'width', 'height'],
    },
  ),
  ToolSchema(
    name: 'inject_text',
    description: 'Input text on the device',
    parameters: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Text to input'},
      },
      'required': ['text'],
    },
  ),
  ToolSchema(
    name: 'inject_key',
    description: 'Inject a key event (e.g. Home=3, Back=4)',
    parameters: {
      'type': 'object',
      'properties': {
        'keycode': {
          'type': 'integer',
          'description': 'Android KeyEvent keycode',
        },
        'action': {
          'type': 'integer',
          'description': 'Key action: 0=down, 1=up (default: 0)',
        },
      },
      'required': ['keycode'],
    },
  ),
  ToolSchema(
    name: 'press_back',
    description: 'Press the Back button',
    parameters: {},
  ),
  ToolSchema(
    name: 'start_app',
    description: 'Launch an app by package name',
    parameters: {
      'type': 'object',
      'properties': {
        'package': {
          'type': 'string',
          'description': 'Android package name of the app to launch',
        },
      },
      'required': ['package'],
    },
  ),
  ToolSchema(
    name: 'set_screen_power',
    description: 'Turn the screen on/off',
    parameters: {
      'type': 'object',
      'properties': {
        'mode': {
          'type': 'string',
          'description': 'Power mode: on | off',
        },
      },
      'required': ['mode'],
    },
  ),
];

void main() {
  group('PhoneAgent', () {
    PhoneAgent makeAgent(
      List<LlmResponse> responses, {
      ToolExecutor? executor,
      int maxSteps = 10,
    }) => PhoneAgent(
      config: AgentConfig(maxSteps: maxSteps),
      llmClient: _FakeLlmClient(responses),
      tools: _agentTools,
      executeToolCall:
          executor ??
          (_, __) async => (text: 'ok', imageBase64: null, imageMimeType: null),
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
          LlmResponse(
            toolCalls: [
              const ToolCall(
                id: 'c1',
                name: 'take_screenshot',
                arguments: '{}',
              ),
            ],
          ),
          const LlmResponse(text: 'Done'),
        ],
        executor: (name, _) async {
          executed.add(name);
          return (
            text: 'screenshot taken',
            imageBase64: null,
            imageMimeType: null,
          );
        },
      ).run('check screen');

      expect(result.success, isTrue);
      expect(executed, ['take_screenshot']);
      expect(result.steps, 2);
    });

    test('feeds tool result back into message history', () async {
      final capturingFake = _CapturingLlmClient([
        LlmResponse(
          toolCalls: [
            const ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
          ],
        ),
        const LlmResponse(text: 'Done'),
      ]);

      final capturingAgent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        llmClient: capturingFake,
        tools: _agentTools,
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
          (_) => LlmResponse(
            toolCalls: [
              const ToolCall(
                id: 'c1',
                name: 'take_screenshot',
                arguments: '{}',
              ),
            ],
          ),
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
          LlmResponse(
            toolCalls: [
              const ToolCall(id: 'c1', name: 'bad_tool', arguments: '{}'),
            ],
          ),
          const LlmResponse(text: 'Recovered after error'),
        ],
        executor: (_, __) async => throw Exception('network fail'),
      ).run('test recovery');

      expect(result.success, isTrue);
      expect(result.result, 'Recovered after error');
    });
  });
}
