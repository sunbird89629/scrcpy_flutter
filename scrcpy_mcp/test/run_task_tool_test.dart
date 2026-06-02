import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/src/agent/agent_config.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:test/test.dart';

import 'real_device_test_utils.dart';

// Fake LLM that immediately completes the task with a finish() action.
class _DoneLlmClient implements LlmClient {
  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
  }) async =>
      const LlmResponse(text: 'finish(message="Task done")');
}

// Records every control message and advertises a *video* resolution that
// differs from the screenshot, to prove touch coordinates use the screenshot
// space rather than the (maxSize-scaled) video space.
class _RecordingSession extends MockScrcpySession {
  final sentMessages = <ScrcpyControlMessage>[];

  @override
  int? get videoWidth => isConnected ? 461 : null;
  @override
  int? get videoHeight => isConnected ? 1024 : null;

  @override
  void sendControlMessage(ScrcpyControlMessage message) =>
      sentMessages.add(message);
}

// Returns a 1080×2400 PNG (only the IHDR header matters for dimension parsing).
class _BigScreenshotAdb extends MockAdb {
  @override
  Future<Uint8List> takeScreenshot(String deviceId) async => Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + "IHDR"
        0x00, 0x00, 0x04, 0x38, // width  = 1080
        0x00, 0x00, 0x09, 0x60, // height = 2400
      ]);
}

// Returns one Tap, then finishes.
class _TapThenFinishLlm implements LlmClient {
  int _i = 0;
  @override
  Future<LlmResponse> chat({required List<LlmMessage> messages}) async =>
      _i++ == 0
          ? const LlmResponse(text: 'do(action="Tap", element=[540,1200])')
          : const LlmResponse(text: 'finish(message="done")');
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
        llmClient: _DoneLlmClient(),
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

    test('touch uses screenshot resolution, not scrcpy video resolution',
        () async {
      final session = _RecordingSession();
      final server = ScrcpyMcpServer(
        session: session,
        adb: _BigScreenshotAdb(),
        agentConfig: const AgentConfig(maxSteps: 5),
        llmClient: _TapThenFinishLlm(),
      );
      final (c, closeFn) = await connectMcpPair(server);
      addTearDown(closeFn);

      await c.callTool(
        const CallToolRequest(
          name: 'run_task',
          arguments: {'device_id': 'device1', 'message': 'tap something'},
        ),
      );

      final touch =
          session.sentMessages.whereType<ScrcpyInjectTouchMessage>().first;
      expect(touch.x, 540);
      expect(touch.y, 1200);
      // Screenshot is 1080×2400 but video is 461×1024 — the touch frame must
      // match the screenshot the model saw, otherwise every tap is mis-scaled.
      expect(touch.width, 1080);
      expect(touch.height, 2400);
    });
  });
}
