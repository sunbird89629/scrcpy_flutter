import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
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
  });
}
