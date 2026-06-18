import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/src/agent/agent_config.dart';
import 'package:scrcpy_mcp/src/agent/agent_model_client.dart';
import 'package:scrcpy_mcp/src/recording_adb.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';

class McpHttpServer {
  StreamableMcpServer? _server;
  int? _port;

  String? get serverUrl => _port != null ? 'http://localhost:$_port/mcp' : null;

  Future<void> start({
    required int port,
    required ScrcpySession session,
    required ScrcpyAdb adb,
    RecordingAdb? recordingAdb,
    AgentConfig? agentConfig,
    AgentModelClient? client,
  }) async {
    _server = StreamableMcpServer(
      serverFactory: (_) => ScrcpyMcpServer(
        session: session,
        adb: adb,
        recordingAdb: recordingAdb,
        agentConfig: agentConfig,
        client: client,
      ).mcpServer,
      port: port,
      enableDnsRebindingProtection: false,
    );
    await _server!.start();
    _port = port;
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    _port = null;
  }
}
