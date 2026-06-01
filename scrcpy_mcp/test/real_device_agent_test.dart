/// Real-device integration test for run_task.
///
/// Requires:
///   - A connected Android device
///   - AUTOGLM_API_KEY env var set
///   - SCRCPY_MCP_TEST_DEVICE env var set to the device serial
///
/// Run with:
///   dart test test/real_device_agent_test.dart
@TestOn('vm')
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'real_device_test_utils.dart';

void main() {
  const deviceId = String.fromEnvironment('SCRCPY_MCP_TEST_DEVICE');

  group('run_task real device', () {
    late McpClient client;
    late Future<void> Function() close;

    setUpAll(() async {
      final scrcpyAdb = ScrcpyMcpAdb(AdbClient());
      final session = await ScrcpySessionImpl.create(adb: scrcpyAdb);

      final server = ScrcpyMcpServer(
        session: session,
        adb: scrcpyAdb,
        agentConfig: AgentConfig.fromEnv(),
        llmClient: AutoglmLlmClient.fromEnv(),
      );
      (client, close) = await connectMcpPair(server);
    });

    tearDownAll(() => close());

    test(
      'run_task completes a simple task',
      () async {
        final result = await client.callTool(
          CallToolRequest(
            name: 'run_task',
            arguments: {'device_id': deviceId, 'message': '截一张屏幕截图并描述当前界面'},
          ),
        );
        expect(result.isError, isFalse);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
