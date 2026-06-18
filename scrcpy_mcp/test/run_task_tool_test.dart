import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/src/agent/agent_config.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:test/test.dart';

import 'real_device_test_utils.dart';
import 'utils/fake_model_client.dart';

// Fake chat that immediately completes the task with a finish() action.
Future<LlmResponse> _doneChat({required List<LlmMessage> messages}) async =>
    const LlmResponse(text: 'finish(message="Task done")');

// Returns one Tap, then finishes.
ChatFn _tapThenFinishChat() {
  var i = 0;
  return ({required List<LlmMessage> messages}) async => i++ == 0
      ? const LlmResponse(text: 'do(action="Tap", element=[540,1200])')
      : const LlmResponse(text: 'finish(message="done")');
}

// Returns one Type, then finishes.
ChatFn _typeThenFinishChat() {
  var i = 0;
  return ({required List<LlmMessage> messages}) async => i++ == 0
      ? const LlmResponse(text: 'do(action="Type", text="hello")')
      : const LlmResponse(text: 'finish(message="done")');
}

// Fake ADB that returns a foreground package for dumpsys calls.
class _ResumedActivityAdb extends MockAdb {
  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (arguments.contains('activities')) {
      return ProcessResult(
        0,
        0,
        'mResumedActivity: ActivityRecord{x u0 com.demo.app/.Main t1}',
        '',
      );
    }
    return super.shell(arguments, deviceId: deviceId, timeout: timeout);
  }
}

// Records an ordered log of control messages (ScrcpyControlMessage) and
// injected text (String), so tests can assert both content and ordering. Also
// advertises a video resolution to prove touch coords use the 1000×1000 grid.
class _RecordingSession extends MockScrcpySession {
  final events = <Object>[];

  @override
  int? get videoWidth => isConnected ? 461 : null;
  @override
  int? get videoHeight => isConnected ? 1024 : null;

  @override
  void sendControlMessage(ScrcpyControlMessage message) => events.add(message);

  @override
  void injectText(String text) => events.add(text);
}

void main() {
  group('run_task tool', () {
    late McpClient client;
    late Future<void> Function() close;

    setUp(() async {
      final server = ScrcpyMcpServer(
        session: MockScrcpySession(),
        adb: MockAdb(),
        agentConfig: const AgentConfig(maxSteps: 5),
        client: FakeModelClient(_doneChat),
      );
      (client, close) = await connectMcpPair(server);
    });

    tearDown(() => close());

    test('run_task tool is advertised', () async {
      final tools = await client.listTools();
      expect(tools.tools.map((t) => t.name), contains('run_task'));
    });

    test('run_task returns success result', () async {
      final result = await client.callTool(
        const CallToolRequest(
          name: 'run_task',
          arguments: {'device_id': 'device1', 'message': 'open settings'},
        ),
      );

      expect(result.isError, isFalse);
      final json =
          jsonDecode((result.content.first as TextContent).text) as Map;
      expect(json['success'], isTrue);
      expect(json['result'], 'Task done');
      expect(json['steps'], 1);
    });

    test('run_task not advertised when no agent config', () async {
      final serverNoAgent = ScrcpyMcpServer(
        session: MockScrcpySession(),
        adb: MockAdb(),
      );
      final (clientNoAgent, closeNoAgent) = await connectMcpPair(serverNoAgent);
      addTearDown(closeNoAgent);

      final tools = await clientNoAgent.listTools();
      expect(tools.tools.map((t) => t.name), isNot(contains('run_task')));
    });

    test('touch coordinates use the 1000×1000 normalized grid', () async {
      final session = _RecordingSession();
      final server = ScrcpyMcpServer(
        session: session,
        adb: MockAdb(),
        agentConfig: const AgentConfig(maxSteps: 5),
        client: FakeModelClient(_tapThenFinishChat()),
      );
      final (c, closeFn) = await connectMcpPair(server);
      addTearDown(closeFn);

      await c.callTool(
        const CallToolRequest(
          name: 'run_task',
          arguments: {'device_id': 'device1', 'message': 'tap something'},
        ),
      );

      final touch = session.events.whereType<ScrcpyInjectTouchMessage>().first;
      // autoglm-phone emits [0,1000] coordinates; scrcpy scales them against
      // the frame size. Passing the raw coord with a 1000×1000 frame lands at
      // x/1000×deviceW. Must NOT be the video resolution (461×1024).
      expect(touch.x, 540);
      expect(touch.y, 1200);
      expect(touch.width, 1000);
      expect(touch.height, 1000);
    });

    test('Type clears the field before injecting text', () async {
      final session = _RecordingSession();
      final server = ScrcpyMcpServer(
        session: session,
        adb: MockAdb(),
        agentConfig: const AgentConfig(maxSteps: 5),
        client: FakeModelClient(_typeThenFinishChat()),
      );
      final (c, closeFn) = await connectMcpPair(server);
      addTearDown(closeFn);

      await c.callTool(
        const CallToolRequest(
          name: 'run_task',
          arguments: {'device_id': 'device1', 'message': 'type something'},
        ),
      );

      // The injected text must come last, after a clear sequence.
      final textIndex = session.events.indexWhere((e) => e is String);
      expect(textIndex, greaterThan(0));
      expect(session.events[textIndex], 'hello');

      final keysBeforeText = session.events
          .take(textIndex)
          .whereType<ScrcpyInjectKeyMessage>();
      // Ctrl+A select-all (keycode 29 with a Ctrl modifier) then Del (67).
      expect(
        keysBeforeText.any((k) => k.keycode == 29 && k.metastate != 0),
        isTrue,
        reason: 'expected Ctrl+A select-all before typing',
      );
      expect(
        keysBeforeText.any((k) => k.keycode == 67),
        isTrue,
        reason: 'expected Del to clear the field before typing',
      );
    });
  });

  group('run_task SOP memory', () {
    test('writes a SOP after a successful run', () async {
      final dir = Directory.systemTemp.createTempSync('sop_rt');
      addTearDown(() => dir.deleteSync(recursive: true));

      final server = ScrcpyMcpServer(
        session: MockScrcpySession(),
        adb: _ResumedActivityAdb(),
        agentConfig: AgentConfig(maxSteps: 5, sopDir: dir.path),
        client: FakeModelClient(({required List<LlmMessage> messages}) async {
          // If the writer's summary prompt is detected, return JSON.
          final isSummary = messages.any(
            (m) => (m.textContent ?? '').contains('请总结成 JSON'),
          );
          return isSummary
              ? const LlmResponse(
                  text: '{"intent":"打开应用","steps":["点图标"],"pitfall":null}',
                )
              : const LlmResponse(text: 'finish(message="done")');
        }),
      );

      final (c, closeFn) = await connectMcpPair(server);
      addTearDown(closeFn);

      await c.callTool(
        const CallToolRequest(
          name: 'run_task',
          arguments: {'device_id': 'device1', 'message': '打开应用'},
        ),
      );

      final f = File('${dir.path}/sop/com.demo.app.jsonl');
      expect(f.existsSync(), isTrue);
      expect(f.readAsStringSync(), contains('"intent":"打开应用"'));
    });
  });
}
