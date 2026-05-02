import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class McpHttpServer {
  StreamableMcpServer? _server;
  int? _port;

  String? get serverUrl => _port != null ? 'http://localhost:$_port/mcp' : null;

  Future<void> start({
    required int port,
    required ScrcpyViewController viewController,
    required ScrcpyAdb adb,
  }) async {
    _server = StreamableMcpServer(
      serverFactory: (_) => ScrcpyMcpServer(
        viewController: viewController,
        adb: adb,
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
