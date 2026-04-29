import 'package:flutter/foundation.dart';
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_packet.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';
import 'package:scrcpy_view/src/scrcpy_stream_parser.dart';

import 'scrcpy_server.dart';

/// Controller for `ScrcpyView` that exposes lifecycle control and device input
/// to external code.
///
/// Pass an instance to `ScrcpyView.controller`. The widget attaches itself on
/// mount and detaches on dispose. Use [addListener] / `ListenableBuilder` to
/// react to state changes.
///
/// Example:
/// ```dart
/// final controller = ScrcpyViewController();
///
/// ScrcpyView(
///   adb: myAdb,
///   deviceId: '11081FDD4004DY',
///   controller: controller,
/// )
///
/// // Later:
/// controller.injectKey(ScrcpyKeycode.home);
/// await controller.stop();
/// ```
class ScrcpyViewController extends ChangeNotifier {
  ScrcpyServer? _server;
  Future<void> Function()? _restartCallback;

  bool _isStarted = false;
  bool _isStarting = false;
  String? _error;

  // ── Readable state ────────────────────────────────────────────────────────

  /// Whether mirroring is currently active.
  bool get isStarted => _isStarted;

  /// Whether mirroring is in the process of starting.
  bool get isStarting => _isStarting;

  /// Last error message, or null if no error has occurred.
  String? get error => _error;

  /// Device metadata (name, width, height) once the stream has started.
  ScrcpyMetadata? get metadata => _server?.currentMetadata;

  /// URL of the web-based video player served by the active session.
  String? get playerUrl => _server?.playerUrl;

  /// Stream of raw scrcpy packets for advanced consumers.
  Stream<ScrcpyPacket>? get packets => _server?.packets;

  // ── Internal protocol (called by ScrcpyView) ─────────────────────────────
  // These methods are annotated @internal and must not be called from outside
  // the scrcpy_view package.

  /// @nodoc
  @internal
  void attachServer(
    ScrcpyServer server,
    Future<void> Function() restartCallback,
  ) {
    _server = server;
    _restartCallback = restartCallback;
    notifyListeners();
  }

  /// @nodoc
  @internal
  void markStarting() {
    _isStarting = true;
    _error = null;
    notifyListeners();
  }

  /// @nodoc
  @internal
  void markStarted() {
    _isStarted = true;
    _isStarting = false;
    notifyListeners();
  }

  /// @nodoc
  @internal
  void markStopped() {
    _isStarted = false;
    _isStarting = false;
    notifyListeners();
  }

  /// @nodoc
  @internal
  void markError(String message) {
    _error = message;
    _isStarting = false;
    notifyListeners();
  }

  /// @nodoc
  @internal
  void detachServer() {
    _server = null;
    _restartCallback = null;
    _isStarted = false;
    _isStarting = false;
    _error = null;
    notifyListeners();
  }

  // ── Public control API ────────────────────────────────────────────────────

  /// Starts (or restarts) the mirroring session.
  ///
  /// No-op if the controller is not attached to a mounted `ScrcpyView`.
  Future<void> start() => _restartCallback?.call() ?? Future.value();

  /// Stops the active mirroring session.
  Future<void> stop() async => _server?.stop();

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
