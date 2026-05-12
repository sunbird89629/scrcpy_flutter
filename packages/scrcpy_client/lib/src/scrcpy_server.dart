import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_adb.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_packet.dart';
import 'package:scrcpy_client/src/scrcpy_stream_parser.dart';

/// Manages a scrcpy server instance on a device.
class ScrcpyServer {
  /// The scrcpy server version bundled with this package.
  static const serverVersion = '3.3.4';

  ScrcpyServer({
    required this.adb,
    required this.deviceId,
    required Uint8List serverJarBytes,
    this.port = 27183,
    ScrcpyLogger logger = const NoOpScrcpyLogger(),
    StreamSink<List<int>>? controlSink,
  })  : _serverJarBytes = serverJarBytes,
        _log = logger,
        _controlSink = controlSink,
        _parser = ScrcpyStreamParser(logger: logger);

  final ScrcpyAdb adb;
  final String deviceId;
  final int port;

  final Uint8List _serverJarBytes;
  final ScrcpyLogger _log;
  final ScrcpyStreamParser _parser;
  bool _isStarting = false;

  Process? _serverProcess;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final StreamSink<List<int>>? _controlSink;
  Socket? _videoSocket;
  Socket? _controlSocket;
  StreamSubscription<Uint8List>? _videoSubscription;

  int? _actualPort;

  /// Stream of parsed scrcpy packets (video frames).
  Stream<ScrcpyPacket> get packets => _parser.packets;

  /// Stream of scrcpy metadata (device name, codec info).
  Stream<ScrcpyMetadata> get metadata => _parser.metadata;

  /// Last parsed metadata, or `null` if the header has not arrived yet.
  ScrcpyMetadata? get currentMetadata => _parser.currentMetadata;

  /// Starts the scrcpy server: pushes JAR, sets up ADB forward,
  /// launches the on-device process, and connects video + control sockets.
  Future<void> start() async {
    if (_isStarting) return;
    _isStarting = true;

    try {
      _log.info('[ScrcpyServer] Starting for device: $deviceId');
      await _pushServer();

      const scid = '12345678';
      const socketName = 'scrcpy_12345678';

      await _setupForwardWithRetry(socketName);
      await _runServer(scid);
      await _connectAll();
    } finally {
      _isStarting = false;
    }
  }

  /// Sends a control message to the device.
  void sendControlMessage(ScrcpyControlMessage message) {
    final sink = _controlSink ?? _controlSocket;
    if (sink == null) {
      _log.warn('[ScrcpyServer] Cannot send control message: Not connected');
      return;
    }
    sink.add(message.toBinary());
  }

  Future<void> _pushServer() async {
    const version = serverVersion;
    const remotePath = '/data/local/tmp/scrcpy-server-v$version.jar';

    try {
      _log.debug('[ScrcpyServer] Writing server JAR to temp file');
      final tempDir = Directory.systemTemp;
      final localTempFile = File(
        p.join(tempDir.path, 'scrcpy-server-v$version.jar'),
      );
      await localTempFile.writeAsBytes(_serverJarBytes, flush: true);
      _log.debug('[ScrcpyServer] Pushing server to device: $remotePath');
      await adb.push(localTempFile.path, remotePath, deviceId: deviceId);
      await localTempFile.delete();
    } on Exception catch (e, st) {
      _log.error('[ScrcpyServer] Failed to prepare server on device', e, st);
      rethrow;
    }
  }

  Future<void> _setupForwardWithRetry(String socketName) async {
    const maxRetries = 10;
    var currentPort = port;

    for (var i = 0; i < maxRetries; i++) {
      try {
        _log.debug(
          '[ScrcpyServer] Setting up forward: tcp:$currentPort'
          ' -> localabstract:$socketName',
        );
        try {
          await adb.forwardRemove('tcp:$currentPort', deviceId: deviceId);
        } catch (_) {}
        await adb.forward(
          'tcp:$currentPort',
          'localabstract:$socketName',
          deviceId: deviceId,
        );
        _actualPort = currentPort;
        return;
      } on Exception catch (e) {
        _log.warn(
          '[ScrcpyServer] Failed to forward on port $currentPort, retrying...',
          e,
        );
        currentPort++;
      }
    }
    throw Exception(
      'Failed to setup port forwarding after $maxRetries attempts',
    );
  }

  Future<void> _runServer(String scidHex) async {
    const version = serverVersion;
    const remotePath = '/data/local/tmp/scrcpy-server-v$version.jar';

    try {
      await adb.shell(['pkill', '-f', 'scrcpy-server-v'], deviceId: deviceId);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final args = [
      if (deviceId.isNotEmpty) ...['-s', deviceId],
      'shell',
      'CLASSPATH=$remotePath',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      version,
      'scid=$scidHex',
      'tunnel_forward=true',
      'video_codec=h264',
      'audio=false',
      'control=true',
      'cleanup=true',
      'max_size=1024',
      'max_fps=60',
      'video_bit_rate=6000000',
      'list_encoders=false',
      'list_displays=false',
      'send_dummy_byte=true',
      'video_codec_options=i-frame-interval=1,latency=1',
      'power_on=true',
    ];

    _log.debug('[ScrcpyServer] Executing: adb ${args.join(' ')}');
    _serverProcess = await Process.start(adb.adbPath, args);

    _stdoutSubscription = _serverProcess!.stdout
        .transform(utf8.decoder)
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) _log.debug('[ScrcpyServer:stdout] $trimmed');
    });

    _stderrSubscription = _serverProcess!.stderr
        .transform(utf8.decoder)
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      if (trimmed.contains('ERROR') || trimmed.contains('Exception')) {
        _log.error('[ScrcpyServer:stderr] $trimmed');
      } else {
        _log.warn('[ScrcpyServer:stderr] $trimmed');
      }
    });

    unawaited(
      _serverProcess!.exitCode.then((code) {
        _log.warn('[ScrcpyServer] server process exited with code $code');
        _parser.close();
      }),
    );

    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> _connectAll() async {
    _videoSocket = await _connectSocket('Video');

    var isFirstByteHandled = false;
    _videoSubscription = _videoSocket!.listen(
      (data) {
        if (!isFirstByteHandled) {
          isFirstByteHandled = true;
          if (data.isNotEmpty && data[0] == 0) {
            if (data.length > 1) _parser.feed(Uint8List.sublistView(data, 1));
            return;
          }
        }
        _parser.feed(data);
      },
      onDone: () => _log.warn('[ScrcpyServer] Video socket closed'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    _controlSocket = await _connectSocket('Control');
    // Without TCP_NODELAY, sub-MTU control messages (DOWN/MOVE/UP) are batched,
    // collapsing gesture timing and breaking velocity-sensitive input handling.
    _controlSocket!.setOption(SocketOption.tcpNoDelay, true);
    _controlSocket!.listen(
      (data) => _log.debug('[ScrcpyServer] Control data: ${data.length} bytes'),
      onDone: () => _log.warn('[ScrcpyServer] Control socket closed'),
    );

    _log.info('[ScrcpyServer] All sockets connected with SCID 0.');
  }

  Future<Socket> _connectSocket(String name) async {
    const maxAttempts = 30;
    const retryDelay = Duration(milliseconds: 500);
    final connectPort = _actualPort ?? port;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _log.debug(
          '[ScrcpyServer] [$name] Connecting to localhost:$connectPort'
          ' (attempt $attempt)',
        );
        return await Socket.connect('localhost', connectPort);
      } on Exception catch (e) {
        if (attempt >= maxAttempts) rethrow;
        _log.debug('[ScrcpyServer] [$name] attempt $attempt failed: $e');
        await Future<void>.delayed(retryDelay);
      }
    }
    throw Exception('Failed to connect to $name socket');
  }

  /// Stops the scrcpy server and releases all resources.
  Future<void> stop() async {
    _log.info('[ScrcpyServer] Stopping for device: $deviceId');

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    await _videoSubscription?.cancel();
    _videoSubscription = null;
    await _videoSocket?.close();
    _videoSocket = null;
    await _controlSocket?.close();
    _controlSocket = null;

    _serverProcess?.kill();
    _serverProcess = null;

    final cleanupPort = _actualPort ?? port;
    try {
      await adb.forwardRemove('tcp:$cleanupPort', deviceId: deviceId);
    } catch (_) {}

    _parser.close();
  }
}
