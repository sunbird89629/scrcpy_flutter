import 'package:flutter/foundation.dart';
import 'package:scrcpy_view/src/backends/scrcpy_video_backend.dart';
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_adb.dart';
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';

/// Controller for `ScrcpyView` that owns the device mirroring session
/// and exposes input injection to external code.
///
/// Create an instance, call [start] to begin mirroring, and pass the
/// controller to `ScrcpyView`. Call [stop] to end the session. Dispose
/// when the controller is no longer needed.
///
/// Example:
/// ```dart
/// final controller = ScrcpyViewController();
///
/// await controller.start(myAdb, '11081FDD4004DY');
///
/// ScrcpyView(controller: controller)
///
/// // Later:
/// controller.injectKey(ScrcpyKeycode.home);
/// await controller.stop();
/// controller.dispose();
/// ```
class ScrcpyViewController extends ChangeNotifier {
  ScrcpyServer? _server;
  bool _pending = false;
  VoidCallback? _onStopped;

  /// Touch event forwarder passed to the video backend.
  late final ScrcpyTouchController touchController = ScrcpyTouchController(
    (msg) => _server?.sendControlMessage(msg),
  );

  // ── Readable state ────────────────────────────────────────────────────────

  /// Whether a mirroring session is currently active.
  bool get isConnected => _server != null;

  /// Whether a session is starting or active. Use to disable the Start button.
  bool get isActive => _pending || _server != null;

  /// The active `ScrcpyServer`, or `null` if no session is active.
  ScrcpyServer? get server => _server;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts a mirroring session for [deviceId].
  ///
  /// No-ops if a session is already starting or active.
  Future<void> start(
    ScrcpyAdb adb,
    String deviceId, {
    ScrcpyLogger logger = const NoOpScrcpyLogger(),
    VoidCallback? onStarted,
    VoidCallback? onStopped,
    ValueChanged<String>? onError,
  }) async {
    if (_pending || _server != null) return;
    _pending = true;
    _onStopped = onStopped;
    notifyListeners();

    final server = ScrcpyServer(adb: adb, deviceId: deviceId, logger: logger);
    try {
      await server.start();
      _server = server;
      _pending = false;
      notifyListeners();
      onStarted?.call();
    } catch (e) {
      logger.error('[ScrcpyViewController] Failed to start: $e', e);
      _pending = false;
      _onStopped = null;
      notifyListeners();
      onError?.call(e.toString());
    }
  }

  /// Stops the active mirroring session.
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
  void injectText(String text) {
    sendControlMessage(ScrcpyInjectTextMessage(text));
  }
}
