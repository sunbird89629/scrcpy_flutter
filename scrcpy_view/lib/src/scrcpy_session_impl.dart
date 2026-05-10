import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_adb.dart';
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';
import 'package:scrcpy_view/src/scrcpy_session.dart';

/// Pure-Dart implementation of [ScrcpySession] wrapping [ScrcpyServer].
///
/// No Flutter dependency — safe for use in CLI tools and MCP servers.
/// For Flutter consumers, use [ScrcpyViewController] which extends
/// `ChangeNotifier` and delegates to this class.
class ScrcpySessionImpl implements ScrcpySession {
  ScrcpySessionImpl({
    required ScrcpyAdb adb,
    required Uint8List serverJarBytes,
    required Uint8List webPlayerBytes,
  })  : _adb = adb,
        _serverJarBytes = serverJarBytes,
        _webPlayerBytes = webPlayerBytes;

  final ScrcpyAdb _adb;
  final Uint8List _serverJarBytes;
  final Uint8List _webPlayerBytes;

  ScrcpyServer? _server;
  bool _running = false;
  bool _pending = false;
  void Function()? _onStopped;

  /// Whether the UI should consider the current session running.
  bool get running => _running;
  set running(bool value) => _running = value;

  @override
  bool get isConnected => _server != null;

  /// Whether a session is starting or active.
  bool get isActive => _pending || _server != null;

  /// The active [ScrcpyServer], or `null` if no session is active.
  ScrcpyServer? get server => _server;

  @override
  String? get proxyUrl => _server?.proxyUrl;

  @override
  String? get playerUrl => _server?.playerUrl;

  @override
  int? get videoWidth => _server?.currentMetadata?.width;

  @override
  int? get videoHeight => _server?.currentMetadata?.height;

  Future<List<String>> getDevices() => _adb.getDevices();

  @override
  Future<void> start(
    String deviceId, {
    ScrcpyLogger? logger,
    void Function()? onStarted,
    void Function()? onStopped,
    void Function(String)? onError,
  }) async {
    if (_pending || _server != null) return;
    _pending = true;
    _onStopped = onStopped;

    final server = ScrcpyServer(
      adb: _adb,
      deviceId: deviceId,
      serverJarBytes: _serverJarBytes,
      webPlayerBytes: _webPlayerBytes,
      logger: logger ?? const NoOpScrcpyLogger(),
    );
    try {
      await server.start();
      _server = server;
      _pending = false;
      onStarted?.call();
    } catch (e) {
      onError?.call(e.toString());
      rethrow;
    } finally {
      _pending = false;
      _onStopped = null;
    }
  }

  @override
  Future<void> stop() async {
    final server = _server;
    final onStopped = _onStopped;
    _server = null;
    _pending = false;
    _onStopped = null;
    await server?.stop();
    onStopped?.call();
  }

  @override
  void sendControlMessage(ScrcpyControlMessage message) {
    _server?.sendControlMessage(message);
  }

  void injectKey(int keycode, {int metastate = 0}) {
    sendControlMessage(ScrcpyInjectKeyMessage(
      action: ScrcpyAction.down,
      keycode: keycode,
      metastate: metastate,
    ));
    sendControlMessage(ScrcpyInjectKeyMessage(
      action: ScrcpyAction.up,
      keycode: keycode,
      metastate: metastate,
    ));
  }

  @override
  void injectText(String text) {
    sendControlMessage(ScrcpyInjectTextMessage(text));
  }

  /// Creates a [ScrcpySessionImpl] by resolving assets from the filesystem.
  ///
  /// If [assetsPath] is provided, assets are loaded from that directory.
  /// Otherwise, assets are located relative to this package's source via
  /// [Isolate.resolvePackageUri].
  static Future<ScrcpySessionImpl> create({
    required ScrcpyAdb adb,
    String? assetsPath,
  }) async {
    Uint8List serverJar;
    Uint8List webPlayer;

    if (assetsPath != null) {
      final dir = Directory(assetsPath);
      serverJar = await File(
        p.join(dir.path, 'scrcpy-server-v3.3.4'),
      ).readAsBytes();
      webPlayer = await File(
        p.join(dir.path, 'web_player', 'index.html'),
      ).readAsBytes();
    } else {
      final libUri = await Isolate.resolvePackageUri(
        Uri.parse('package:scrcpy_view/scrcpy_core.dart'),
      );
      if (libUri == null) {
        throw StateError(
          'Cannot resolve scrcpy_view package path. '
          'Use the --assets-path argument to specify the assets directory.',
        );
      }
      final packageRoot = libUri.resolve('../');
      serverJar = await File.fromUri(
        packageRoot.resolve('assets/scrcpy-server-v3.3.4'),
      ).readAsBytes();
      webPlayer = await File.fromUri(
        packageRoot.resolve('assets/web_player/index.html'),
      ).readAsBytes();
    }

    return ScrcpySessionImpl(
      adb: adb,
      serverJarBytes: serverJar,
      webPlayerBytes: webPlayer,
    );
  }
}
