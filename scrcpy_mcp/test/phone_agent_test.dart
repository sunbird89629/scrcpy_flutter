import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:scrcpy_mcp/src/agent/action_summary.dart';
import 'package:test/test.dart';

import 'utils/fake_model_client.dart';

/// Returns a [ChatFn] that replays a fixed sequence of [LlmResponse] values.
ChatFn _fakeChat(List<LlmResponse> responses) {
  var i = 0;
  return ({required List<LlmMessage> messages}) async => responses[i++];
}

/// Returns a [ChatFn] that replays responses and records every call's messages
/// into [capturedMessages].
ChatFn _capturingChat(List<LlmResponse> responses,
    List<List<LlmMessage>> capturedMessages) {
  var i = 0;
  return ({required List<LlmMessage> messages}) async {
    capturedMessages.add(List.from(messages));
    return responses[i++];
  };
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
      client: FakeModelClient(_fakeChat(responses)),
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
      final captured = <List<LlmMessage>>[];
      final chatFn = _capturingChat([
        const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
        const LlmResponse(text: 'finish(message="Done")'),
      ], captured);

      final capturingAgent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        client: FakeModelClient(chatFn),
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await capturingAgent.run('tap something');

      // First call: system + user (with screenshot)
      final firstCallMessages = captured[0];
      expect(firstCallMessages.any((m) => m.role == 'user'), isTrue);
      final userMsg = firstCallMessages.firstWhere((m) => m.role == 'user');
      expect(userMsg.imageBase64, isNotNull);
      expect(userMsg.textContent, 'tap something');

      // Second call: system + user + assistant + user (with new screenshot)
      final secondCallMessages = captured[1];
      expect(secondCallMessages.any((m) => m.role == 'assistant'), isTrue);
      final lastMsg = secondCallMessages.last;
      expect(lastMsg.imageBase64, isNotNull);
    });

    test(
      'feeds the previous action result into the next user message',
      () async {
        final captured = <List<LlmMessage>>[]; final chatFn = _capturingChat([
          const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
          const LlmResponse(text: 'finish(message="done")'),
        ], captured);

        final agent = PhoneAgent(
          config: const AgentConfig(maxSteps: 5),
          client: FakeModelClient(chatFn),
          takeScreenshot: _fakeScreenshot,
          actionRunner: (_) async => 'Tapped (540, 1200)',
        );

        await agent.run('do it');

        // The second call's latest user turn carries the prior action's result,
        // not a constant prompt — this is what gives feedback and breaks the
        // repetition-collapse failure mode.
        final secondCall = captured[1];
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
      final captured = <List<LlmMessage>>[]; final chatFn = _capturingChat([
        const LlmResponse(
          text:
              '<think>这里是冗长的推理过程</think>'
              'do(action="Tap", element=[1,2])',
        ),
        const LlmResponse(text: 'finish(message="done")'),
      ], captured);

      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        client: FakeModelClient(chatFn),
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await agent.run('go');

      final secondCall = captured[1];
      final assistant = secondCall.firstWhere((m) => m.role == 'assistant');
      expect(assistant.textContent, isNot(contains('推理过程')));
      expect(assistant.textContent, isNot(contains('<think>')));
      expect(assistant.textContent, contains('do(action'));
    });

    test('keeps only the last keepScreenshots screenshots in history', () async {
      final captured = <List<LlmMessage>>[]; final chatFn = _capturingChat([
        const LlmResponse(text: 'do(action="Tap", element=[500,300])'),
        const LlmResponse(text: 'do(action="Tap", element=[600,400])'),
        const LlmResponse(text: 'do(action="Tap", element=[700,500])'),
        const LlmResponse(text: 'do(action="Tap", element=[800,600])'),
        const LlmResponse(text: 'finish(message="Done")'),
      ], captured);

      // Distinct screenshot per step so each is unique (and stall detection
      // never trips).
      var shot = 0;
      Future<({String base64, String mimeType})> distinctScreenshot() async =>
          (base64: 'frame-${shot++}', mimeType: 'image/png');

      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 6, keepScreenshots: 2),
        client: FakeModelClient(chatFn),
        takeScreenshot: distinctScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await agent.run('tap repeatedly');

      // Last call (the finish step) carries 5 prior user screenshots, but only
      // the 2 most recent should retain their image.
      final lastCall = captured.last;
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
        client: FakeModelClient(
          _fakeChat(
            List.generate(
              30,
              (_) => const LlmResponse(
                text: 'do(action="Swipe", start=[499,614], end=[499,263])',
              ),
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

    test('injects memory into user messages', () async {
      final captured = <List<LlmMessage>>[]; final chatFn = _capturingChat([
        const LlmResponse(
          text:
              '<think>t</think><memory>视频1: A - 1万</memory>do(action="Tap", element=[1,2])',
        ),
        const LlmResponse(text: 'finish(message="done")'),
      ], captured);

      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        client: FakeModelClient(chatFn, memoryEnabled: true),
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await agent.run('collect videos');

      // The second call's user message (step 0's feedback) should carry the memory.
      final secondCall = captured[1];
      final lastUser = secondCall.lastWhere((m) => m.role == 'user');
      expect(lastUser.textContent, contains('跨步记录'));
      expect(lastUser.textContent, contains('视频1: A - 1万'));
    });

    test('uses the client systemPromptTemplate as the system message', () async {
      final captured = <List<LlmMessage>>[];
      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 1, screenSize: (1080, 2400)),
        client: FakeModelClient(
          _capturingChat(
            [const LlmResponse(text: 'finish(message="done")')],
            captured,
          ),
          systemPromptTemplate: 'HELLO {SCREEN_SIZE}',
        ),
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await agent.run('task');

      final system = captured.first.first;
      expect(system.role, 'system');
      expect(system.textContent, 'HELLO 1080x2400');
    });

    test('stores only the do() action line in history, stripping prose', () async {
      final captured = <List<LlmMessage>>[];
      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 2),
        client: FakeModelClient(
          _capturingChat([
            const LlmResponse(
              text: '好的，我需要点击。\ndo(action="Tap", element=[100,200])',
            ),
            const LlmResponse(text: 'finish(message="done")'),
          ], captured),
        ),
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await agent.run('task');

      final assistantTurns = captured[1]
          .where((m) => m.role == 'assistant')
          .map((m) => m.textContent)
          .toList();
      expect(assistantTurns, ['do(action="Tap", element=[100,200])']);
    });

    test('returns action trajectory and injects guidance', () async {
      final seen = <String>[];
      var i = 0;
      final client = FakeModelClient(({required messages}) async {
        // capture the step-0 user text to assert guidance injection
        for (final m in messages) {
          if (m.role == 'user' && m.textContent != null) seen.add(m.textContent!);
        }
        return i++ == 0
            ? const LlmResponse(text: 'do(action="Tap", element=[1,2])')
            : const LlmResponse(text: 'finish(message="done")');
      });
      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        client: client,
        takeScreenshot: () async => (base64: 'AAA$i', mimeType: 'image/png'),
        actionRunner: (a) async => 'ok',
      );
      final result = await agent.run('开门', guidance: '参考：先点首页');
      expect(result.success, isTrue);
      expect(result.trajectory, isNotEmpty);
      expect(result.trajectory.first, contains('Tap'));
      expect(seen.any((t) => t.contains('参考：先点首页')), isTrue);
    });

  });

  group('actionSummary', () {
    test('Tap shows coordinates', () {
      expect(
        actionSummary(const DoAction(action: 'Tap', element: [897, 939])),
        'Tap(897,939)',
      );
    });

    test('Swipe shows start→end', () {
      expect(
        actionSummary(
          const DoAction(action: 'Swipe', start: [499, 702], end: [499, 263]),
        ),
        'Swipe(499,702→499,263)',
      );
    });

    test('Wait shows the raw duration', () {
      expect(
        actionSummary(const DoAction(action: 'Wait', duration: '2 seconds')),
        'Wait(2 seconds)',
      );
    });

    test('Launch shows the app', () {
      expect(
        actionSummary(const DoAction(action: 'Launch', app: 'Chrome')),
        'Launch(Chrome)',
      );
    });

    test('Type shows quoted text', () {
      expect(
        actionSummary(const DoAction(action: 'Type', text: '张三')),
        'Type("张三")',
      );
    });

    test('long text is truncated with an ellipsis', () {
      final s = actionSummary(DoAction(action: 'Type', text: '一' * 30));
      expect(s, startsWith('Type("'));
      expect(s, contains('…'));
    });

    test('Back renders without parens', () {
      expect(actionSummary(const DoAction(action: 'Back')), 'Back');
    });

    test('Note shows its message', () {
      expect(
        actionSummary(const DoAction(action: 'Note', message: 'True')),
        'Note("True")',
      );
    });

    test('Finish shows quoted message', () {
      expect(actionSummary(const FinishAction('done')), 'Finish("done")');
    });

    test('Long Press and Double Tap show coordinates', () {
      expect(
        actionSummary(const DoAction(action: 'Long Press', element: [1, 2])),
        'Long Press(1,2)',
      );
      expect(
        actionSummary(const DoAction(action: 'Double Tap', element: [3, 4])),
        'Double Tap(3,4)',
      );
    });

    test('Type_Name shows quoted text', () {
      expect(
        actionSummary(const DoAction(action: 'Type_Name', text: '李四')),
        'Type_Name("李四")',
      );
    });

    test('Home renders without parens', () {
      expect(actionSummary(const DoAction(action: 'Home')), 'Home');
    });

    test('missing coordinates render as ?', () {
      expect(actionSummary(const DoAction(action: 'Tap')), 'Tap(?)');
      expect(actionSummary(const DoAction(action: 'Swipe')), 'Swipe(?→?)');
    });
  });
}
