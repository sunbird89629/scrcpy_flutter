import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

// Fake that replays a fixed sequence of LlmResponse values.
class _FakeLlmClient implements LlmClient {
  _FakeLlmClient(this._responses);
  final List<LlmResponse> _responses;
  int _i = 0;

  @override
  Future<LlmResponse> chat({required List<LlmMessage> messages}) async =>
      _responses[_i++];
}

class _CapturingLlmClient implements LlmClient {
  _CapturingLlmClient(this._responses);
  final List<LlmResponse> _responses;
  final capturedMessages = <List<LlmMessage>>[];
  int _i = 0;

  @override
  Future<LlmResponse> chat({required List<LlmMessage> messages}) async {
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
    }) => PhoneAgent(
      config: AgentConfig(maxSteps: maxSteps),
      llmClient: _FakeLlmClient(responses),
      takeScreenshot: _fakeScreenshot,
      actionRunner: actionRunner ?? (_) async => 'ok',
    );

    test('returns failure when LLM output has no parseable action', () async {
      final result = await makeAgent([
        const LlmResponse(text: 'Task complete'),
      ]).run('open settings');

      expect(result.success, isFalse);
      expect(result.result, contains('Could not parse an action'));
      expect(result.result, contains('Task complete'));
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

    test('Interact aborts as needs-human without running it', () async {
      var ran = false;
      final result = await makeAgent(
        [const LlmResponse(text: 'do(action="Interact")')],
        actionRunner: (_) async {
          ran = true;
          return 'ok';
        },
      ).run('pick one');

      expect(result.success, isFalse);
      expect(result.result, contains('requires human'));
      expect(ran, isFalse, reason: 'Interact must not reach the action runner');
      expect(result.steps, 1);
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

    test(
      'feeds the previous action result into the next user message',
      () async {
        final capturingFake = _CapturingLlmClient([
          const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
          const LlmResponse(text: 'finish(message="done")'),
        ]);

        final agent = PhoneAgent(
          config: const AgentConfig(maxSteps: 5),
          llmClient: capturingFake,
          takeScreenshot: _fakeScreenshot,
          actionRunner: (_) async => 'Tapped (540, 1200)',
        );

        await agent.run('do it');

        // The second call's latest user turn carries the prior action's result,
        // not a constant prompt — this is what gives feedback and breaks the
        // repetition-collapse failure mode.
        final secondCall = capturingFake.capturedMessages[1];
        final lastUser = secondCall.lastWhere((m) => m.role == 'user');
        expect(lastUser.textContent, contains('Tapped (540, 1200)'));
      },
    );

    test('retries once on a truncated (length) response', () async {
      final result = await makeAgent([
        // Unparseable garbage, flagged as truncated by max_tokens.
        const LlmResponse(text: '重复重复重复没有动作', finishReason: 'length'),
        const LlmResponse(text: 'finish(message="recovered")'),
      ]).run('do it');

      // The agent recovers within the same step instead of failing.
      expect(result.success, isTrue);
      expect(result.result, 'recovered');
      expect(result.steps, 1);
    });

    test(
      'does not retry an unparseable response that was not truncated',
      () async {
        final result = await makeAgent([
          const LlmResponse(text: '没有动作的普通文本'),
        ]).run('do it');

        expect(result.success, isFalse);
        expect(result.result, contains('Could not parse an action'));
        expect(result.steps, 1);
      },
    );

    test('strips <think> blocks from assistant history', () async {
      final capturingFake = _CapturingLlmClient([
        const LlmResponse(
          text:
              '<think>这里是冗长的推理过程</think>'
              'do(action="Tap", element=[1,2])',
        ),
        const LlmResponse(text: 'finish(message="done")'),
      ]);

      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        llmClient: capturingFake,
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await agent.run('go');

      final secondCall = capturingFake.capturedMessages[1];
      final assistant = secondCall.firstWhere((m) => m.role == 'assistant');
      expect(assistant.textContent, isNot(contains('推理过程')));
      expect(assistant.textContent, isNot(contains('<think>')));
      expect(assistant.textContent, contains('do(action'));
    });

    test('keeps only the last keepScreenshots screenshots in history', () async {
      final capturingFake = _CapturingLlmClient([
        const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
        const LlmResponse(text: 'do(action="Tap", element=[600,400])'),
        const LlmResponse(text: 'do(action="Tap", element=[700,500])'),
        const LlmResponse(text: 'do(action="Tap", element=[800,600])'),
        const LlmResponse(text: 'finish(message="Done")'),
      ]);

      // Distinct screenshot per step so each is unique (and stall detection
      // never trips).
      var shot = 0;
      Future<({String base64, String mimeType})> distinctScreenshot() async =>
          (base64: 'frame-${shot++}', mimeType: 'image/png');

      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 6, keepScreenshots: 2),
        llmClient: capturingFake,
        takeScreenshot: distinctScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await agent.run('tap repeatedly');

      // Last call (the finish step) carries 5 prior user screenshots, but only
      // the 2 most recent should retain their image.
      final lastCall = capturingFake.capturedMessages.last;
      final withImages = lastCall.where((m) => m.imageBase64 != null).toList();
      expect(withImages.length, 2);
      // The retained images are the two most recent frames.
      expect(withImages.map((m) => m.imageBase64), ['frame-3', 'frame-4']);

      // Older user messages keep their text but drop the screenshot.
      final staleUserMsgs = lastCall
          .where((m) => m.role == 'user' && m.imageBase64 == null)
          .toList();
      expect(staleUserMsgs, isNotEmpty);
      expect(staleUserMsgs.first.textContent, contains('历史截图已省略'));
    });

    test(
      'aborts when the screen is unchanged for stallThreshold steps',
      () async {
        // Model keeps guessing taps; the fake screenshot never changes.
        final result = await makeAgent(
          List.generate(
            8,
            (_) =>
                const LlmResponse(text: 'do(action="Tap", element=[499,577])'),
          ),
        ).run('dismiss a dialog that will not move');

        expect(result.success, isFalse);
        expect(result.result, contains('unchanged'));
        // stallThreshold defaults to 3: aborts at step index 3 → 4 steps.
        expect(result.steps, 4);
      },
    );

    test('aborts when the same action repeats too many times', () async {
      // Distinct screenshot per step so the screen-unchanged stall never fires;
      // only the action-repeat backstop can catch this loop (like scrolling a
      // list forever with an identical Swipe).
      var shot = 0;
      Future<({String base64, String mimeType})> distinctScreenshot() async =>
          (base64: 'frame-${shot++}', mimeType: 'image/png');

      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 30),
        llmClient: _FakeLlmClient(
          List.generate(
            30,
            (_) => const LlmResponse(
              text: 'do(action="Swipe", start=[499,614], end=[499,263])',
            ),
          ),
        ),
        takeScreenshot: distinctScreenshot,
        actionRunner: (_) async => 'ok',
      );

      final result = await agent.run('scroll forever');

      expect(result.success, isFalse);
      expect(result.result, contains('repeated the same action'));
      // repeatedActionThreshold defaults to 10 → aborts at the 10th identical
      // action (above a reasonable scroll budget, so bounded scrolling is safe).
      expect(result.steps, 10);
    });

    test('returns failure when max steps reached', () async {
      final result = await makeAgent(
        List.generate(
          3,
          (_) => const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
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
      final action = ActionParser.parse('do(action="Tap", element=[500, 300])');
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

    test('finish() tolerates unescaped inner quotes in message', () {
      // Real autoglm-phone output: natural-language prefix + finish() whose
      // message contains unescaped inner quotes around 「Twitter（X）的主页」.
      const content =
          '否，界面上没有出现"Twitter（X）的主页"。当前显示的是Google的界面。\n'
          'finish(message="否，界面上没有出现"Twitter（X）的主页"。当前显示的是Google的界面。")';
      final action = ActionParser.parse(content);

      expect(action, isA<FinishAction>());
      final finish = action! as FinishAction;
      // Message is extracted cleanly: no `message="` wrapper leaking in, and
      // the inner quotes are preserved verbatim.
      expect(finish.message, startsWith('否，界面上没有出现'));
      expect(finish.message, isNot(contains('message=')));
      expect(finish.message, contains('"Twitter（X）的主页"'));
      expect(finish.message, endsWith('Google的界面。'));
    });

    test('parses Type_Name do() into text', () {
      final action = ActionParser.parse('do(action="Type_Name", text="张三")');
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Type_Name');
      expect(doAction.text, '张三');
    });

    test('parses Interact do() with no args', () {
      final action = ActionParser.parse('do(action="Interact")');
      expect(action, isA<DoAction>());
      expect((action! as DoAction).action, 'Interact');
    });

    test('parses Note do() into message', () {
      final action = ActionParser.parse('do(action="Note", message="True")');
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Note');
      expect(doAction.message, 'True');
    });

    test('parses Call_API instruction into message', () {
      final action = ActionParser.parse(
        'do(action="Call_API", instruction="总结当前页面")',
      );
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Call_API');
      expect(doAction.message, '总结当前页面');
    });

    test('parses sensitive Tap with message', () {
      final action = ActionParser.parse(
        'do(action="Tap", element=[10, 20], message="重要操作")',
      );
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Tap');
      expect(doAction.element, [10, 20]);
      expect(doAction.message, '重要操作');
    });

    test('parses Type_Name shorthand into text', () {
      final action = ActionParser.parse('Type_Name("李四")');
      expect(action, isA<DoAction>());
      final doAction = action! as DoAction;
      expect(doAction.action, 'Type_Name');
      expect(doAction.text, '李四');
    });
  });
}
