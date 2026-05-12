import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:scrcpy_view/src/backends/scrcpy_video_backend.dart';
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_adb.dart';
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';
import 'package:scrcpy_view/src/scrcpy_session.dart';
import 'package:scrcpy_view/src/scrcpy_session_impl.dart';

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

  ScrcpySessionImpl? _impl;

  /// Touch event forwarder passed to the video backend.
  // ignore: prefer_function_declarations_over_variables
  late final ScrcpyTouchCallback touchController =
      (msg) => _impl?.sendControlMessage(msg);

  /// Returns the current ADB device serials from the injected ADB bridge.
  Future<List<String>> getDevices() =>
      _impl?.getDevices() ?? _adb.getDevices();

  // ── Readable state ────────────────────────────────────────────────────────

  /// Whether the UI should consider the current session running.
  bool get running => _impl?.running ?? false;

  /// Updates the running flag and notifies listeners.
  set running(bool value) {
    if (_impl != null) _impl!.running = value;
    notifyListeners();
  }

  @override
  bool get isConnected => _impl != null;

  /// Whether a session is starting or active. Use to disable the Start button.
  bool get isActive => _impl?.isActive ?? false;

  /// The active `ScrcpyServer`, or `null` if no session is active.
  ScrcpyServer? get server => _impl?.server;

  @override
  String? get proxyUrl => _impl?.proxyUrl;

  @override
  String? get playerUrl => _impl?.playerUrl;

  @override
  int? get videoWidth => _impl?.videoWidth;

  @override
  int? get videoHeight => _impl?.videoHeight;

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
    if (_impl != null) return;
    notifyListeners();

    try {
      const version = ScrcpyServer.serverVersion;
      final serverJarData = await rootBundle.load(
        'packages/scrcpy_view/assets/scrcpy-server-v$version',
      );
      final serverJarBytes = serverJarData.buffer.asUint8List();

      final webPlayerData = await rootBundle.load(
        'packages/scrcpy_view/assets/web_player/index.html',
      );
      final webPlayerBytes = webPlayerData.buffer.asUint8List();

      _impl = ScrcpySessionImpl(
        adb: _adb,
        serverJarBytes: serverJarBytes,
        webPlayerBytes: webPlayerBytes,
      );
    } catch (e) {
      notifyListeners();
      onError?.call(e.toString());
      rethrow;
    }

    try {
      await _impl!.start(
        deviceId,
        logger: logger,
        onStarted: () {
          notifyListeners();
          onStarted?.call();
        },
        onStopped: onStopped,
        onError: onError,
      );
    } catch (e) {
      _impl = null;
      notifyListeners();
      rethrow;
    }
  }

  /// Stops the active mirroring session.
  @override
  Future<void> stop() async {
    final impl = _impl;
    _impl = null;
    notifyListeners();
    await impl?.stop();
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
    _impl?.sendControlMessage(message);
  }

  /// Injects a key event (down + up) for the given Android keycode.
  void injectKey(int keycode, {int metastate = 0}) {
    _impl?.injectKey(keycode, metastate: metastate);
  }

  /// Injects text into the focused field on the device.
  @override
  void injectText(String text) {
    _impl?.injectText(text);
  }
}
