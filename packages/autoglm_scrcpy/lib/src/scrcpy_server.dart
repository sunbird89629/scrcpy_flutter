import 'dart:async';
import 'dart:io';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_scrcpy/src/scrcpy_packet.dart';
import 'package:autoglm_scrcpy/src/scrcpy_proxy_server.dart';
import 'package:autoglm_scrcpy/src/scrcpy_stream_parser.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages scrcpy server lifecycle on a device.
class ScrcpyServer {
  /// Creates a new [ScrcpyServer].
  ScrcpyServer({
    required this.adbClient,
    required this.deviceId,
    this.port = 27183,
  });

  /// The ADB client to use.
  final AdbClient adbClient;

  /// The device ID.
  final String deviceId;

  /// The local TCP port to forward scrcpy socket to.
  final int port;

  Process? _serverProcess;
  Socket? _socket;
  StreamSubscription<List<int>>? _socketSubscription;
  final _parser = ScrcpyStreamParser();
  final _proxy = ScrcpyProxyServer();

  /// Stream of parsed scrcpy packets.
  Stream<ScrcpyPacket> get packets => _parser.packets;

  /// Stream of scrcpy metadata.
  Stream<ScrcpyMetadata> get metadata => _parser.metadata;

  /// The FIFO path of the H264 proxy server for video players.
  String get proxyFifoPath => _proxy.fifoPath;

  /// Starts the scrcpy server.
  Future<void> start() async {
    print('[ScrcpyServer] Starting...');
    await _deployServer();
    print('[ScrcpyServer] Server deployed');
    await _setupForward();
    print('[ScrcpyServer] Port forwarded to $port');
    await _runServer();
    print('[ScrcpyServer] Server process running');
    await _connect();
    print('[ScrcpyServer] Connected to socket');
    await _proxy.start(packets);
    print('[ScrcpyServer] Proxy FIFO: $proxyFifoPath');
  }

  Future<void> _deployServer() async {
    // 1. Get scrcpy-server asset
    final data = await rootBundle.load(
      'packages/autoglm_scrcpy/assets/scrcpy-server-v3.3.3',
    );
    final bytes = data.buffer.asUint8List();

    // 2. Write to app support dir (more reliable than temp)
    final supportDir = await getApplicationSupportDirectory();
    final binDir = Directory(p.join(supportDir.path, 'bin'));
    binDir.createSync(recursive: true);

    final localPath = p.join(binDir.path, 'scrcpy-server-v3.3.3');
    await File(localPath).writeAsBytes(bytes);

    // 3. Push to device
    const remotePath = '/data/local/tmp/scrcpy-server';
    await adbClient.push(localPath, remotePath, deviceId: deviceId);

    // Ensure it's executable on the device
    await adbClient.shell(['chmod', '755', remotePath], deviceId: deviceId);
  }

  Future<void> _setupForward() async {
    await adbClient.forward(
      'tcp:$port',
      'localabstract:scrcpy',
      deviceId: deviceId,
    );
  }

  Future<void> _runServer() async {
    // Kill any existing scrcpy server first
    try {
      await adbClient.shell(
        ['pkill', '-9', '-f', 'scrcpy-server'],
        deviceId: deviceId,
      );
    } on Exception catch (_) {}

    // Start scrcpy server via app_process
    final args = [
      if (deviceId.isNotEmpty) ...['-s', deviceId],
      'shell',
      'CLASSPATH=/data/local/tmp/scrcpy-server',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      '3.3.3',
      'tunnel_forward=true',
      'control=false',
      'audio=false',
      'send_dummy_byte=true',
    ];

    _serverProcess = await Process.start(adbClient.adbPath, args);

    // Give it a moment to start
    await Future<void>.delayed(const Duration(seconds: 1));

    if (await _serverProcess!.exitCode.timeout(
          const Duration(milliseconds: 100),
          onTimeout: () => -1,
        ) !=
        -1) {
      throw const AdbException('Scrcpy server failed to start immediately.');
    }
  }

  Future<void> _connect() async {
    // Connect to forwarded port
    var attempts = 0;
    while (attempts < 5) {
      try {
        _socket = await Socket.connect('localhost', port);
        break;
      } on Exception catch (_) {
        attempts++;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    if (_socket == null) {
      throw const AdbException('Failed to connect to scrcpy server socket.');
    }

    _socketSubscription = _socket!.listen(
      (data) => _parser.feed(Uint8List.fromList(data)),
      onDone: stop,
      onError: (_) => stop(),
    );
  }

  /// Stops the scrcpy server and cleans up.
  Future<void> stop() async {
    await _proxy.stop();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
    _serverProcess?.kill();
    _serverProcess = null;
    try {
      await adbClient.forwardRemove('tcp:$port', deviceId: deviceId);
    } on Exception catch (_) {}
    _parser.close();
  }
}
