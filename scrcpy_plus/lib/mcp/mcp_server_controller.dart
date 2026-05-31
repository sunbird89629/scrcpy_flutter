import 'package:adb_tools/adb_tools.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

/// Owns the embedded MCP HTTP server lifecycle for scrcpy_plus.
///
/// Wraps scrcpy_mcp's [McpHttpServer]: builds a [ScrcpyMcpAdb] from the app's
/// [AdbClient], creates a [ScrcpySession], and starts/stops a single shared
/// Streamable HTTP MCP endpoint. Startup failures are captured into
/// [errorMessage] rather than thrown, so the tray app keeps running.
class McpServerController {
  McpServerController({
    required AdbClient adb,
    ScrcpySession? session,
  })  : _adb = ScrcpyMcpAdb(adb),
        _injectedSession = session;

  final ScrcpyMcpAdb _adb;
  final McpHttpServer _server = McpHttpServer();
  final ScrcpySession? _injectedSession;

  bool _running = false;
  String? _errorMessage;

  bool get isRunning => _running;
  String? get serverUrl => _server.serverUrl;
  String? get errorMessage => _errorMessage;

  /// Start the MCP server on [port]. Captures failures into [errorMessage].
  Future<void> start(int port) async {
    if (_running) return;
    _errorMessage = null;
    try {
      final session = _injectedSession ?? await _createSession();
      await _server.start(
        port: port,
        session: session,
        adb: _adb,
        recordingAdb: _adb,
      );
      _running = true;
    } catch (e) {
      _errorMessage = e.toString();
      _running = false;
    }
  }

  /// Builds a real session by loading the scrcpy-server JAR from the bundled
  /// Flutter assets.
  ///
  /// We deliberately avoid [ScrcpySessionImpl.create], whose default path uses
  /// `Isolate.resolvePackageUri` — that only works under `dart run` (JIT) and
  /// throws "Unsupported operation" in an AOT-compiled Flutter app. Loading via
  /// [rootBundle] is the approach used by scrcpy_view.
  Future<ScrcpySession> _createSession() async {
    const version = ScrcpyServer.serverVersion;
    final jarData = await rootBundle.load(
      'packages/scrcpy_client/assets/scrcpy-server-v$version',
    );
    return ScrcpySessionImpl(
      adb: _adb,
      serverJarBytes: jarData.buffer.asUint8List(),
    );
  }

  Future<void> stop() async {
    await _server.stop();
    _running = false;
  }
}
