import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:scrcpy_view/src/backends/scrcpy_video_backend.dart';
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_adb.dart';
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';
import 'package:scrcpy_view/src/scrcpy_session.dart';

/// Controller for `ScrcpyView` that owns the device mirroring session
/// and exposes input injection to external code.
///
/// Create an instance, call [start] to begin mirroring, and pass the
/// controller to `ScrcpyView`. Call [stop] to end the session. Dispose
/// when the controller is no longer needed.
///
/// Example:
/// ```dart
/// final controller = ScrcpyViewController(adb: myAdb);
///
/// await controller.start('11081FDD4004DY');
///
/// ScrcpyView(controller: controller)
///
/// // Later:
/// controller.injectKey(ScrcpyKeycode.home);
/// await controller.stop();
/// controller.dispose();
/// ```
class ScrcpyViewController extends ChangeNotifier implements ScrcpySession {
  /// Creates a controller backed by an injected ADB bridge.
  ScrcpyViewController({
    required ScrcpyAdb adb,
  }) : _adb = adb {
    PlatformInAppWebViewController.debugLoggingSettings.excludeFilter
        .add(RegExp('statsHandler'));
  }

  final ScrcpyAdb _adb;
  // final ScrcpyLogger _logger;

  ScrcpyServer? _server;
  bool _running = false;
  bool _pending = false;
  VoidCallback? _onStopped;

  /// Whether the UI should consider the current session running.
  bool get running => _running;

  /// Updates the running flag and notifies listeners.
  set running(bool value) {
    _running = value;
    notifyListeners();
  }

  /// Touch event forwarder passed to the video backend.
  late final ScrcpyTouchController touchController = ScrcpyTouchController(
    (msg) => _server?.sendControlMessage(msg),
  );

  /// Returns the current ADB device serials from the injected ADB bridge.
  Future<List<String>> getDevices() => _adb.getDevices();

  // ── Readable state ────────────────────────────────────────────────────────

  /// Whether a mirroring session is currently active.
  @override
  bool get isConnected => _server != null;

  /// Whether a session is starting or active. Use to disable the Start button.
  bool get isActive => _pending || _server != null;

  /// The active `ScrcpyServer`, or `null` if no session is active.
  ScrcpyServer? get server => _server;

  @override
  String? get proxyUrl => _server?.proxyUrl;

  @override
  String? get playerUrl => _server?.playerUrl;

  /// Starts a mirroring session for [deviceId].
  ///
  /// No-ops if a session is already starting or active.
  @override
  Future<void> start(
    String deviceId, {
    ScrcpyLogger? logger,
    VoidCallback? onStarted,
    VoidCallback? onStopped,
    ValueChanged<String>? onError,
  }) async {
    if (_pending || _server != null) return;
    _pending = true;
    _onStopped = onStopped;
    notifyListeners();

    final server = ScrcpyServer(
      adb: _adb,
      deviceId: deviceId,
    );
    try {
      await server.start();
      _server = server;
      _pending = false;
      notifyListeners();
      onStarted?.call();
    } catch (e) {
      onError?.call(e.toString());
      rethrow;
    } finally {
      _pending = false;
      _onStopped = null;
      notifyListeners();
    }
  }

  /// Stops the active mirroring session.
  @override
  Future<void> stop() async {
    final server = _server;
    final onStopped = _onStopped;
    _server = null;
    _pending = false;
    _onStopped = null;
    notifyListeners();
    await server?.stop();
    onStopped?.call();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ── Public control API ────────────────────────────────────────────────────

  /// Sends a raw control message to the device.
  @override
  void sendControlMessage(ScrcpyControlMessage message) {
    _server?.sendControlMessage(message);
  }

  /// Injects a key event (down + up) for the given Android keycode.
  void injectKey(int keycode, {int metastate = 0}) {
    sendControlMessage(
      ScrcpyInjectKeyMessage(
        action: ScrcpyAction.down,
        keycode: keycode,
        metastate: metastate,
      ),
    );
    sendControlMessage(
      ScrcpyInjectKeyMessage(
        action: ScrcpyAction.up,
        keycode: keycode,
        metastate: metastate,
      ),
    );
  }

  /// Injects text into the focused field on the device.
  @override
  void injectText(String text) {
    sendControlMessage(ScrcpyInjectTextMessage(text));
  }
}
