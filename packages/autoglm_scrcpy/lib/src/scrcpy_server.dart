import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/src/control_message.dart';
import 'package:autoglm_scrcpy/src/scrcpy_packet.dart';
import 'package:autoglm_scrcpy/src/scrcpy_proxy_server.dart';
import 'package:autoglm_scrcpy/src/scrcpy_stream_parser.dart';
import 'package:autoglm_scrcpy/src/scrcpy_websocket_server.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages a scrcpy server instance on a device.
class ScrcpyServer {
  /// Creates a new [ScrcpyServer].
  ScrcpyServer({
    required this.adbClient,
    required this.deviceId,
    this.port = 27183,
  })  : _proxy = ScrcpyProxyServer(),
        _wsProxy = ScrcpyWebsocketServer(),
        _parser = ScrcpyStreamParser();

  /// The ADB client to use.
  final AdbClient adbClient;

  /// The device ID to run scrcpy on.
  final String deviceId;

  /// The preferred local port to forward to the scrcpy server.
  final int port;

  /// The actual port being used after dynamic selection.
  int? _actualPort;

  final ScrcpyProxyServer _proxy;
  final ScrcpyWebsocketServer _wsProxy;
  final ScrcpyStreamParser _parser;
  bool _isStarting = false;

  int? _scid;
  Process? _serverProcess;
  Socket? _videoSocket;
  Socket? _controlSocket;
  StreamSubscription<Uint8List>? _videoSubscription;

  /// The URL for the media player to connect to (MPEG-TS/HTTP).
  String get proxyUrl => _proxy.proxyUrl;

  /// The URL for the web-based player (HTML/JS).
  String get playerUrl => _wsProxy.playerUrl;

  /// Resolves after the proxy has buffered SPS/PPS + first keyframe, so a
  /// media client opening [proxyUrl] immediately gets a decodable burst.
  Future<void> get proxyReady => _proxy.ready;

  /// Stream of parsed scrcpy packets.
  Stream<ScrcpyPacket> get packets => _parser.packets;

  /// Stream of scrcpy metadata.
  Stream<ScrcpyMetadata> get metadata => _parser.metadata;

  /// Last parsed metadata, or `null` if the header has not arrived yet. Lets
  /// late subscribers recover the one-shot broadcast that fires on start-up.
  ScrcpyMetadata? get currentMetadata => _parser.currentMetadata;

  /// Starts the scrcpy server.
  Future<void> start() async {
    if (_isStarting) return;
    _isStarting = true;

    try {
      appLogger.i('[ScrcpyServer] Starting for device: $deviceId');

      // 1. Prepare the server binary and web player on the host
      final webPlayerPath = await _prepareWebPlayer();
      await _pushServer();

      // 2. Use scid 0 and socket name scrcpy_00000000 for simplicity
      _scid = 0;
      final socketName = 'scrcpy_00000000';

      // 3. Setup port forwarding with retry logic for port conflicts
      await _setupForwardWithRetry(socketName);

      // 4. Run the server process
      await _runServer('00000000');

      // 5. Subscribe the proxy BEFORE any data flows so SPS/PPS isn't missed.
      await _proxy.start(_parser.packets);
      await _wsProxy.start(_parser.packets, staticPath: webPlayerPath);
      appLogger.i('[ScrcpyServer] Proxy Media URL: ${_proxy.proxyUrl}');
      appLogger.i('[ScrcpyServer] Web Player URL: $playerUrl');

      // 6. Connect to the forwarded port (retries while server is warming up).
      await _connectAll();
    } finally {
      _isStarting = false;
    }
  }

  /// Sends a control message to the device.
  void sendControlMessage(ScrcpyControlMessage message) {
    final socket = _controlSocket;
    if (socket == null) {
      appLogger.w('[ScrcpyServer] Cannot send control message: Not connected');
      return;
    }
    socket.add(message.toBinary());
  }

  Future<String> _prepareWebPlayer() async {
    const assetPath = 'packages/autoglm_scrcpy/assets/web_player/index.html';
    try {
      appLogger.d('[ScrcpyServer] Extracting web player asset: $assetPath');
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final webDir = Directory(p.join(tempDir.path, 'autoglm_web_player'))
        ..createSync(recursive: true);
      final indexFile = File(p.join(webDir.path, 'index.html'));
      await indexFile.writeAsBytes(bytes, flush: true);
      return webDir.path;
    } catch (e) {
      appLogger.e('[ScrcpyServer] Failed to prepare web player', e);
      rethrow;
    }
  }

  Future<void> _pushServer() async {
    const version = '3.3.4';
    const assetPath = 'packages/autoglm_scrcpy/assets/scrcpy-server-v$version';
    const remotePath = '/data/local/tmp/scrcpy-server-v$version.jar';

    try {
      appLogger.d('[ScrcpyServer] Extracting server asset: $assetPath');

      // Load from assets
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      // Write to a temporary file on the host machine
      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (_) {
        tempDir = Directory.systemTemp;
      }
      final localTempFile =
          File(p.join(tempDir.path, 'scrcpy-server-v$version.jar'));
      await localTempFile.writeAsBytes(bytes, flush: true);

      appLogger.d('[ScrcpyServer] Pushing server to device: $remotePath');
      await adbClient.push(localTempFile.path, remotePath, deviceId: deviceId);

      // Clean up local temp file
      await localTempFile.delete();
    } catch (e, st) {
      appLogger.e('[ScrcpyServer] Failed to prepare server on device', e, st);
      rethrow;
    }
  }

  Future<void> _setupForwardWithRetry(String socketName) async {
    const maxRetries = 10;
    var currentPort = port;

    for (var i = 0; i < maxRetries; i++) {
      try {
        appLogger.d(
          '[ScrcpyServer] Setting up forward: tcp:$currentPort -> localabstract:$socketName',
        );

        // Always try to remove any stale forward on this port first
        try {
          await adbClient.forwardRemove('tcp:$currentPort', deviceId: deviceId);
        } catch (_) {}

        await adbClient.forward(
          'tcp:$currentPort',
          'localabstract:$socketName',
          deviceId: deviceId,
        );
        _actualPort = currentPort;
        return;
      } catch (e) {
        appLogger.w(
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
    const version = '3.3.4';
    const remotePath = '/data/local/tmp/scrcpy-server-v$version.jar';

    // Best-effort kill of any lingering scrcpy-server app_process instances
    try {
      await adbClient.shell(
        ['pkill', '-f', 'scrcpy-server-v'], // Match any scrcpy-server version
        deviceId: deviceId,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } catch (_) {}

    final args = [
      if (deviceId.isNotEmpty) ...['-s', deviceId],
      'shell',
      'CLASSPATH=$remotePath',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      version,
      'scid=0',
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
      'send_dummy_byte=false',
      'video_codec_options=i-frame-interval=1,latency=1,profile=1',
      'power_on=true',
    ];

    appLogger.d('[ScrcpyServer] Executing: adb ${args.join(' ')}');
    _serverProcess = await Process.start(adbClient.adbPath, args);

    _serverProcess!.stdout.transform(utf8.decoder).listen((line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        appLogger.d('[ScrcpyServer:stdout] $trimmed');
      }
    });

    _serverProcess!.stderr.transform(utf8.decoder).listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      if (trimmed.contains('ERROR') || trimmed.contains('Exception')) {
        appLogger.e('[ScrcpyServer:stderr] $trimmed');
      } else {
        appLogger.w('[ScrcpyServer:stderr] $trimmed');
      }
    });

    unawaited(
      _serverProcess!.exitCode.then((code) async {
        appLogger.w('[ScrcpyServer] server process exited with code $code');
        _parser.close();
        await _proxy.stop();
      }),
    );

    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> _connectAll() async {
    // scrcpy never expects bytes from the client during socket setup. The
    // server identifies sockets purely by accept() order: video, then
    // (audio,) then control. On the first (video) socket, the server sends:
    //   - 1 dummy byte 0x00 (only if send_dummy_byte=true)
    //   - 64 bytes device name + 12 bytes video codec metadata
    //   - then video packets
    // The control socket is bidirectional; the server starts reading control
    // messages from the very first byte we write, so we MUST NOT prepend
    // anything before real ScrcpyControlMessage bytes.

    // 1. Video socket
    _videoSocket = await _connectSocket('Video');

    var isFirstByteHandled = false;
    _videoSubscription = _videoSocket!.listen(
      (data) {
        // Defensive: if the server ever sends a leading 0x00 (dummy byte on
        // the forward tunnel), drop it before handing bytes to the parser.
        if (!isFirstByteHandled) {
          isFirstByteHandled = true;
          if (data.isNotEmpty && data[0] == 0) {
            if (data.length > 1) _parser.feed(Uint8List.sublistView(data, 1));
            return;
          }
        }
        _parser.feed(data);
      },
      onDone: () => appLogger.w('[ScrcpyServer] Video socket closed'),
    );

    // 2. Control socket — accept() order matters; connect after video.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _controlSocket = await _connectSocket('Control');

    _controlSocket!.listen(
      (data) => appLogger.d('[ScrcpyServer] Control data: ${data.length} bytes'),
      onDone: () => appLogger.w('[ScrcpyServer] Control socket closed'),
    );

    appLogger.i('[ScrcpyServer] All sockets connected with SCID 0.');
  }

  Future<Socket> _connectSocket(String name) async {
    const maxAttempts = 30;
    const retryDelay = Duration(milliseconds: 500);
    final connectPort = _actualPort ?? port;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        appLogger.d('[ScrcpyServer] [$name] Connecting to localhost:$connectPort (attempt $attempt)');
        return await Socket.connect('localhost', connectPort);
      } on Exception catch (e) {
        if (attempt >= maxAttempts) rethrow;
        appLogger.d('[ScrcpyServer] [$name] attempt $attempt failed: $e');
        await Future<void>.delayed(retryDelay);
      }
    }
    throw Exception('Failed to connect to $name socket');
  }

  /// Stops the scrcpy server.
  Future<void> stop() async {
    appLogger.i('[ScrcpyServer] Stopping for device: $deviceId');
    
    // 1. Stop data ingestion first
    await _videoSubscription?.cancel();
    _videoSubscription = null;
    await _videoSocket?.close();
    _videoSocket = null;
    await _controlSocket?.close();
    _controlSocket = null;

    // 2. Stop proxies
    await _proxy.stop();
    await _wsProxy.stop();

    // 3. Kill process
    _serverProcess?.kill();
    _serverProcess = null;

    // 4. Remove port forwarding
    final cleanupPort = _actualPort ?? port;
    try {
      await adbClient.forwardRemove('tcp:$cleanupPort', deviceId: deviceId);
    } catch (_) {}
    
    // 5. Close parser
    _parser.close();
  }
}
