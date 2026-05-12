import 'package:flutter/foundation.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class McpServerController extends ChangeNotifier {
  McpServerController({
    required ScrcpySession session,
    required ScrcpyAdb adb,
  })  : _session = session,
        _adb = adb;

  final ScrcpySession _session;
  final ScrcpyAdb _adb;
  final _httpServer = McpHttpServer();

  int _port = 7070;
  bool _running = false;
  String? _errorMessage;

  int get port => _port;
  set port(int value) {
    if (_running) return;
    _port = value;
    notifyListeners();
  }

  bool get isRunning => _running;
  String? get serverUrl => _httpServer.serverUrl;
  String? get errorMessage => _errorMessage;

  Future<void> start() async {
    _errorMessage = null;
    notifyListeners();
    try {
      await _httpServer.start(
        port: _port,
        session: _session,
        adb: _adb,
      );
      _running = true;
    } catch (e) {
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _httpServer.stop();
    _running = false;
    notifyListeners();
  }
}
