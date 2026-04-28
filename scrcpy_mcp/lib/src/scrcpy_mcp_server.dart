import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:scrcpy_adapters/scrcpy_adapters.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// Scrcpy operations exposed for MCP tool integration.
class ScrcpyMcpServer {
  ScrcpyMcpServer({String? adbPath}) : _adb = AdbClient(adbPath: adbPath ?? 'adb');

  final AdbClient _adb;
  ScrcpyServer? _server;

  /// List connected Android devices.
  Future<List<String>> listDevices() async => _adb.listDevices();

  /// Start screen mirroring for a [deviceId].
  Future<ScrcpyServer> startMirroring(String deviceId) async {
    await _server?.stop();
    _server = ScrcpyServer(
      adb: AdbClientAdapter(_adb),
      deviceId: deviceId,
      logger: const AppLoggerAdapter(),
    );
    await _server!.start();
    return _server!;
  }

  /// Stop the active mirroring session.
  Future<void> stopMirroring() async {
    await _server?.stop();
    _server = null;
  }

  /// The current [ScrcpyServer], or `null`.
  ScrcpyServer? get server => _server;

  /// Send a key event.
  void injectKey(int keycode, {int action = ScrcpyAction.down}) {
    _server?.sendControlMessage(
      ScrcpyInjectKeyMessage(action: action, keycode: keycode),
    );
  }

  /// Send a touch event.
  void injectTouch({
    required int x,
    required int y,
    required int width,
    required int height,
    int action = ScrcpyAction.down,
    int pointerId = 0,
  }) {
    _server?.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: action,
        pointerId: pointerId,
        x: x,
        y: y,
        width: width,
        height: height,
      ),
    );
  }

  /// Clean up resources.
  Future<void> dispose() async {
    await _server?.stop();
  }
}
