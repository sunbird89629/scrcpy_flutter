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
  }) async =>
      _responses[_i++];
}

class _CapturingLlmClient implements LlmClient {
  _CapturingLlmClient(this._responses);
  final List<LlmResponse> _responses;
  final capturedMessages = <List<LlmMessage>>[];
  int _i = 0;

  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
  }) async {
    capturedMessages.add(List.from(messages));
    return _responses[_i++];
  }
}

/// Fake screenshot provider — returns a dummy 1x1 PNG.
Future<({String base64, String mimeType})> _fakeScreenshot() async => (
  base64:
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  mimeType: 'image/png',
);

void main() {
  group('PhoneAgent', () {
    PhoneAgent makeAgent(
      List<LlmResponse> responses, {
      ActionRunner? actionRunner,
      int maxSteps = 10,
    }) =>
        PhoneAgent(
          config: AgentConfig(maxSteps: maxSteps),
          llmClient: _FakeLlmClient(responses),
          takeScreenshot: _fakeScreenshot,
          actionRunner: actionRunner ?? (_) async => 'ok',
        );

    test('returns success when LLM returns plain text (no action)', () async {
      final result = await makeAgent([
        const LlmResponse(text: 'Task complete'),
      ]).run('open settings');

      expect(result.success, isTrue);
      expect(result.result, 'Task complete');
      expect(result.steps, 1);
    });

    test('executes action before receiving final answer', () async {
      final executed = <String>[];
      final result = await makeAgent(
        [
          const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
          const LlmResponse(text: 'finish(message="Task done")'),
        ],
        actionRunner: (action) async {
          executed.add('$action');
          return 'ok';
        },
      ).run('tap something');

      expect(result.success, isTrue);
      expect(result.result, 'Task done');
      expect(executed.length, 1);
      expect(executed.first, contains('Tap'));
      expect(result.steps, 2);
    });

    test('feeds screenshot into message history', () async {
      final capturingFake = _CapturingLlmClient([
        const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
        const LlmResponse(text: 'finish(message="Done")'),
      ]);

      final capturingAgent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        llmClient: capturingFake,
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await capturingAgent.run('tap something');

      // First call: system + user (with screenshot)
      final firstCallMessages = capturingFake.capturedMessages[0];
      expect(firstCallMessages.any((m) => m.role == 'user'), isTrue);
      final userMsg = firstCallMessages.firstWhere((m) => m.role == 'user');
      expect(userMsg.imageBase64, isNotNull);
      expect(userMsg.textContent, 'tap something');

      // Second call: system + user + assistant + user (with new screenshot)
      final secondCallMessages = capturingFake.capturedMessages[1];
      expect(secondCallMessages.any((m) => m.role == 'assistant'), isTrue);
      final lastMsg = secondCallMessages.last;
      expect(lastMsg.imageBase64, isNotNull);
    });

    test('returns failure when max steps reached', () async {
      final result = await makeAgent(
        List.generate(
          3,
          (_) => const LlmResponse(
            text: 'do(action="Tap", element=[500,300])',
          ),
        ),
        maxSteps: 3,
      ).run('impossible task');

      expect(result.success, isFalse);
      expect(result.steps, 3);
      expect(result.result, contains('Max steps'));
    });

    test('continues loop when action runner throws', () async {
      final result = await makeAgent(
        [
          const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
          const LlmResponse(text: 'finish(message="Recovered after error")'),
        ],
        actionRunner: (_) async => throw Exception('network fail'),
      ).run('test recovery');

      expect(result.success, isTrue);
      expect(result.result, 'Recovered after error');
    });

    test('parses finish action from model output', () async {
      final result = await makeAgent([
        const LlmResponse(text: 'finish(message="All done successfully")'),
      ]).run('simple task');

      expect(result.success, isTrue);
      expect(result.result, 'All done successfully');
      expect(result.steps, 1);
    });

    test('parses Launch shorthand from model output', () async {
      final executed = <String>[];
      final result = await makeAgent(
        [
          const LlmResponse(text: 'Launch("Chrome")'),
          const LlmResponse(text: 'finish(message="Done")'),
        ],
        actionRunner: (action) async {
          executed.add('$action');
          return 'ok';
        },
      ).run('open chrome');

      expect(result.success, isTrue);
      expect(executed.length, 1);
      expect(executed.first, contains('Launch'));
    });

    test('parses Tap shorthand with coordinates', () async {
      final executed = <String>[];
      final result = await makeAgent(
        [
          const LlmResponse(text: 'Tap([500, 300])'),
          const LlmResponse(text: 'finish(message="Done")'),
        ],
        actionRunner: (action) async {
          executed.add('$action');
          return 'ok';
        },
      ).run('tap screen');

      expect(result.success, isTrue);
      expect(executed.length, 1);
      expect(executed.first, contains('Tap'));
    });

    test('parses screenshot shorthand as FinishAction', () async {
      final result = await makeAgent([
        const LlmResponse(text: 'screenshot(message="Screen captured")'),
      ]).run('capture');

      expect(result.success, isTrue);
      expect(result.result, 'Screen captured');
      expect(result.steps, 1);
    });
  });

  // ── ActionParser unit tests ─────────────────────────────────────────────

  group('ActionParser', () {
    test('parses do() with keywords', () {
      final action = ActionParser.parse(
        'do(action="Tap", element=[500, 300])',
      );
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Tap');
      expect(doAction.element, [500, 300]);
    });

    test('parses Launch shorthand', () {
      final action = ActionParser.parse('Launch("Chrome")');
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Launch');
      expect(doAction.app, 'Chrome');
    });

    test('parses Tap shorthand', () {
      final action = ActionParser.parse('Tap([500, 300])');
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Tap');
      expect(doAction.element, [500, 300]);
    });

    test('parses Back shorthand', () {
      final action = ActionParser.parse('Back()');
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Back');
    });

    test('parses Swipe shorthand with two coordinate pairs', () {
      final action = ActionParser.parse('Swipe([500, 1500], [500, 500])');
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Swipe');
      expect(doAction.start, [500, 1500]);
      expect(doAction.end, [500, 500]);
    });

    test('parses inside <answer> tags', () {
      final action = ActionParser.parse(
        '<answer>do(action="Tap", element=[100, 200])</answer>',
      );
      expect(action, isA<DoAction>());
    });

    test('parses model output with thinking prefix', () {
      final action = ActionParser.parse(
        'Let me launch the browser.\nLaunch("Chrome")',
      );
      expect(action, isA<DoAction>());
    });
  });
}
