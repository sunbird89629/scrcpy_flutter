import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_adb.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_server.dart';
import 'package:scrcpy_client/src/scrcpy_server_options.dart';
import 'package:scrcpy_client/src/scrcpy_session.dart';

/// Pure-Dart implementation of [ScrcpySession] wrapping [ScrcpyServer].
///
/// No Flutter dependency — safe for use in CLI tools and MCP servers.
/// For Flutter consumers, use a separate ScrcpyViewController which extends
/// `ChangeNotifier` and manages proxy/WebSocket server lifecycle.
class ScrcpySessionImpl implements ScrcpySession {
  ScrcpySessionImpl({
    required ScrcpyAdb adb,
    required Uint8List serverJarBytes,
  })  : _adb = adb,
        _serverJarBytes = serverJarBytes;

  final ScrcpyAdb _adb;
  final Uint8List _serverJarBytes;

  ScrcpyServer? _server;
  bool running = false;
  bool _pending = false;
  void Function()? _onStopped;

  @override
  bool get isConnected => _server != null;

  /// Whether a session is starting or active.
  bool get isActive => _pending || _server != null;

  /// The active [ScrcpyServer], or `null` if no session is active.
  ScrcpyServer? get server => _server;

  @override
  int? get videoWidth => _server?.currentMetadata?.width;

  @override
  int? get videoHeight => _server?.currentMetadata?.height;

  Future<List<String>> getDevices() => _adb.getDevices();

  @override
  Future<void> start(
    String deviceId, {
    ScrcpyServerOptions options = const ScrcpyServerOptions(),
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
      options: options,
      logger: logger ?? const NoOpScrcpyLogger(),
    );
    try {
      await server.start();
      _server = server;
      _pending = false;
      onStarted?.call();
    } on Exception catch (e) {
      _pending = false;
      _onStopped = null;
      onError?.call(e.toString());
      rethrow;
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

  /// Creates a [ScrcpySessionImpl] by resolving the JAR asset from the
  /// filesystem.
  ///
  /// If [assetsPath] is provided, the JAR is loaded from that directory.
  /// Otherwise, the JAR is located relative to this package's source via
  /// [Isolate.resolvePackageUri].
  static Future<ScrcpySessionImpl> create({
    required ScrcpyAdb adb,
    String? assetsPath,
  }) async {
    Uint8List serverJar;

    if (assetsPath != null) {
      serverJar = await File(
        p.join(assetsPath, 'scrcpy-server-v${ScrcpyServer.serverVersion}'),
      ).readAsBytes();
    } else {
      final libUri = await Isolate.resolvePackageUri(
        Uri.parse('package:scrcpy_client/scrcpy_client.dart'),
      );
      if (libUri == null) {
        throw StateError(
          'Cannot resolve scrcpy_client package path. '
          'Use the --assets-path argument to specify the assets directory.',
        );
      }
      final packageRoot = libUri.resolve('../');
      serverJar = await File.fromUri(
        packageRoot.resolve(
          'assets/scrcpy-server-v${ScrcpyServer.serverVersion}',
        ),
      ).readAsBytes();
    }

    return ScrcpySessionImpl(adb: adb, serverJarBytes: serverJar);
  }
}
