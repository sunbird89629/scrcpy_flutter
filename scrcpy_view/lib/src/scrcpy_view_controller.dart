import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_view/src/backends/scrcpy_video_backend.dart';
import 'package:scrcpy_view/src/scrcpy_proxy_server.dart';
import 'package:scrcpy_view/src/scrcpy_websocket_server.dart';

/// Controller for `ScrcpyView` that owns the device mirroring session,
/// manages the HTTP/WebSocket proxy servers, and exposes input injection.
///
/// Create an instance, call [start] to begin mirroring, and pass the
/// controller to `ScrcpyView`. Call [stop] to end the session. Dispose
/// when the controller is no longer needed.
///
/// Example:
/// ```dart
/// final controller = ScrcpyViewController(adb: myAdb);
/// await controller.start('11081FDD4004DY');
/// ScrcpyView(controller: controller)
/// // Later:
/// controller.injectKey(ScrcpyKeycode.home);
/// await controller.stop();
/// controller.dispose();
/// ```
class ScrcpyViewController extends ChangeNotifier implements ScrcpySession {
  ScrcpyViewController({required ScrcpyAdb adb}) : _adb = adb {
    PlatformInAppWebViewController.debugLoggingSettings.excludeFilter
        .add(RegExp('statsHandler'));
  }

  final ScrcpyAdb _adb;

  ScrcpySessionImpl? _impl;
  ScrcpyProxyServer? _proxy;
  ScrcpyWebsocketServer? _wsProxy;

  String? _proxyUrl;
  String? _playerUrl;

  /// Touch event forwarder passed to the video backend.
  // ignore: prefer_function_declarations_over_variables
  late final ScrcpyTouchCallback touchController =
      (msg) => _impl?.sendControlMessage(msg);

  Future<List<String>> getDevices() =>
      _impl?.getDevices() ?? _adb.getDevices();

  // ── Readable state ────────────────────────────────────────────────────────

  bool get running => _impl?.running ?? false;

  set running(bool value) {
    if (_impl != null) _impl!.running = value;
    notifyListeners();
  }

  @override
  bool get isConnected => _impl != null;

  bool get isActive => _impl?.isActive ?? false;

  ScrcpyServer? get server => _impl?.server;

  /// HTTP proxy URL for MPEG-TS stream (media_kit), or `null` if not started.
  String? get proxyUrl => _proxyUrl;

  /// WebSocket player URL (web-based player), or `null` if not started.
  String? get playerUrl => _playerUrl;

  /// Resolves after the proxy has buffered SPS/PPS + first keyframe.
  Future<void> get proxyReady => _proxy?.ready ?? Future.value();

  @override
  int? get videoWidth => _impl?.videoWidth;

  @override
  int? get videoHeight => _impl?.videoHeight;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

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

      // JAR now lives in scrcpy_client assets.
      final serverJarData = await rootBundle.load(
        'packages/scrcpy_client/assets/scrcpy-server-v$version',
      );
      final serverJarBytes = serverJarData.buffer.asUint8List();

      // Web player stays in scrcpy_view assets.
      final webPlayerData = await rootBundle.load(
        'packages/scrcpy_view/assets/web_player/index.html',
      );
      final webPlayerBytes = webPlayerData.buffer.asUint8List();

      _impl = ScrcpySessionImpl(adb: _adb, serverJarBytes: serverJarBytes);

      // ScrcpySessionImpl.start() blocks until sockets are connected.
      await _impl!.start(deviceId,
          logger: logger, onStopped: onStopped, onError: onError);

      // Wire up proxy servers directly here (not inside an async onStarted
      // callback) so we can safely await each step.
      final srv = _impl!.server!;
      final webPlayerPath = await _prepareWebPlayer(webPlayerBytes);
      final effectiveLogger = logger ?? const NoOpScrcpyLogger();
      _proxy = ScrcpyProxyServer(logger: effectiveLogger);
      _wsProxy = ScrcpyWebsocketServer(logger: effectiveLogger);

      await Future.wait([
        _proxy!.start(srv.packets),
        _wsProxy!.start(srv.packets, staticPath: webPlayerPath),
      ]);

      _proxyUrl = _proxy!.proxyUrl;
      _playerUrl = _wsProxy!.playerUrl;

      // Stop proxies automatically if the server process exits unexpectedly.
      srv.packets.listen(null, onDone: _stopProxies);

      notifyListeners();
      onStarted?.call();
    } catch (e) {
      _impl = null;
      await _stopProxies();
      notifyListeners();
      onError?.call(e.toString());
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final impl = _impl;
    _impl = null;
    notifyListeners();
    await _stopProxies();
    await impl?.stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ── Control API ───────────────────────────────────────────────────────────

  @override
  void sendControlMessage(ScrcpyControlMessage message) {
    _impl?.sendControlMessage(message);
  }

  void injectKey(int keycode, {int metastate = 0}) {
    _impl?.injectKey(keycode, metastate: metastate);
  }

  @override
  void injectText(String text) {
    _impl?.injectText(text);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _stopProxies() async {
    final proxy = _proxy;
    final wsProxy = _wsProxy;
    _proxy = null;
    _wsProxy = null;
    _proxyUrl = null;
    _playerUrl = null;
    await proxy?.stop();
    await wsProxy?.stop();
  }

  Future<String> _prepareWebPlayer(Uint8List webPlayerBytes) async {
    final tempDir = Directory.systemTemp;
    final webDir = Directory(p.join(tempDir.path, 'autoglm_web_player'))
      ..createSync(recursive: true);
    await File(p.join(webDir.path, 'index.html'))
        .writeAsBytes(webPlayerBytes, flush: true);
    return webDir.path;
  }
}
