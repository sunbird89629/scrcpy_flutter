import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/src/scrcpy_packet.dart';
import 'package:autoglm_scrcpy/src/scrcpy_proxy_server.dart';
import 'package:autoglm_scrcpy/src/scrcpy_stream_parser.dart';
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
        _parser = ScrcpyStreamParser();

  /// The ADB client to use.
  final AdbClient adbClient;

  /// The device ID to run scrcpy on.
  final String deviceId;

  /// The local port to forward to the scrcpy server.
  final int port;

  final ScrcpyProxyServer _proxy;
  final ScrcpyStreamParser _parser;

  Process? _serverProcess;
  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;

  /// The URL for the media player to connect to.
  String get proxyUrl => _proxy.mediaUrl;

  /// Resolves after the proxy has buffered SPS/PPS + first keyframe, so a
  /// media client opening [proxyUrl] immediately gets a decodable burst.
  Future<void> get proxyReady => _proxy.ready;

  /// Stream of parsed scrcpy packets.
  Stream<ScrcpyPacket> get packets => _parser.packets;

  /// Stream of scrcpy metadata.
  Stream<ScrcpyMetadata> get metadata => _parser.metadata;

  /// Starts the scrcpy server.
  Future<void> start() async {
    appLogger.i('[ScrcpyServer] Starting for device: $deviceId');

    // 1. Prepare the server binary on the device
    await _pushServer();

    // 2. Pick a random scid so the abstract socket name is unique per run
    //    (scrcpy server parses `scid=` as HEX and binds `scrcpy_%08x`).
    final scid = Random.secure().nextInt(0x7FFFFFFF);
    final scidHex = scid.toRadixString(16);
    final socketName = 'scrcpy_${scidHex.padLeft(8, '0')}';

    // 3. Setup port forwarding
    await _setupForward(socketName);

    // 4. Run the server process
    await _runServer(scidHex);

    // 5. Subscribe the proxy BEFORE any data flows so SPS/PPS isn't missed.
    await _proxy.start(_parser.packets);
    appLogger.i('[ScrcpyServer] Proxy Media URL: ${_proxy.mediaUrl}');

    // 6. Connect to the forwarded port (retries while server is warming up).
    await _connect();
  }

  Future<void> _pushServer() async {
    const assetPath = 'packages/autoglm_scrcpy/assets/scrcpy-server-v3.3.3';
    const remotePath = '/data/local/tmp/scrcpy-server-v3.3.3.jar';

    try {
      appLogger.d('[ScrcpyServer] Extracting server asset: $assetPath');
      
      // Load from assets
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      // Write to a temporary file on the host machine
      final tempDir = await getTemporaryDirectory();
      final localTempFile = File(p.join(tempDir.path, 'scrcpy-server-v3.3.3.jar'));
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

  Future<void> _setupForward(String socketName) async {
    appLogger.d('[ScrcpyServer] Setting up forward: tcp:$port -> localabstract:$socketName');
    await adbClient.forward(
      'tcp:$port',
      'localabstract:$socketName',
      deviceId: deviceId,
    );
  }

  Future<void> _runServer(String scidHex) async {
    // Best-effort kill of any lingering scrcpy-server app_process instances
    // from a previous crashed run. pkill -f on Android toybox matches against
    // the full command line, so the jar path is a reliable pattern.
    try {
      await adbClient.shell(
        ['pkill', '-f', 'scrcpy-server-v3.3.3.jar'],
        deviceId: deviceId,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } catch (_) {}

    final args = [
      if (deviceId.isNotEmpty) ...['-s', deviceId],
      'shell',
      'CLASSPATH=/data/local/tmp/scrcpy-server-v3.3.3.jar',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      '3.3.3',
      'scid=$scidHex',
      'tunnel_forward=true',
      'audio=false',
      'control=false',
      'cleanup=true',
      'list_encoders=false',
      'list_displays=false',
      'send_dummy_byte=true',
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

    // If the server dies before we ever see a keyframe, fail fast so the UI
    // does not hang on `proxyReady`.
    unawaited(_serverProcess!.exitCode.then((code) async {
      appLogger.w('[ScrcpyServer] server process exited with code $code');
      _parser.close();
      await _proxy.stop();
    }));

    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> _connect() async {
    const maxAttempts = 30;
    const probeTimeout = Duration(seconds: 2);
    const retryDelay = Duration(milliseconds: 500);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      Socket? socket;
      StreamSubscription<Uint8List>? sub;
      try {
        appLogger.d(
          '[ScrcpyServer] Connection attempt $attempt/$maxAttempts to '
          'localhost:$port',
        );
        socket = await Socket.connect('localhost', port);

        // scrcpy with send_dummy_byte=true writes a single 0x00 as soon as the
        // abstract socket is reachable — we wait for that to prove the tunnel
        // is really wired up before feeding bytes into the parser. adb may
        // happily accept + close the forward if the scrcpy server hasn't
        // bound its abstract socket yet, which looks like "connection OK"
        // followed by an immediate EOF.
        final probe = Completer<Uint8List?>();
        sub = socket.listen(
          (data) {
            if (!probe.isCompleted) probe.complete(data);
          },
          onDone: () {
            if (!probe.isCompleted) probe.complete(null);
          },
          onError: (Object e, StackTrace st) {
            if (!probe.isCompleted) probe.completeError(e, st);
          },
        );

        final first = await probe.future.timeout(
          probeTimeout,
          onTimeout: () => null,
        );

        if (first == null || first.isEmpty) {
          appLogger.w(
            '[ScrcpyServer] Attempt $attempt: no data (server still '
            'warming up?), retrying…',
          );
          await sub.cancel();
          await socket.close();
          await Future<void>.delayed(retryDelay);
          continue;
        }

        appLogger.i(
          '[ScrcpyServer] Tunnel ready after $attempt attempt(s); '
          'received ${first.length} bootstrap byte(s)',
        );

        // Swap the probe handler to forward all bytes to the parser, and
        // replay what we already buffered.
        sub
          ..onData((data) => _parser.feed(Uint8List.fromList(data)))
          ..onDone(() => appLogger.w('[ScrcpyServer] Socket closed'))
          ..onError(
            (Object e, StackTrace st) =>
                appLogger.e('[ScrcpyServer] Socket error', e, st),
          );
        _parser.feed(first);
        _socket = socket;
        _socketSubscription = sub;
        return;
      } on Exception catch (e) {
        await sub?.cancel();
        await socket?.close();
        if (attempt >= maxAttempts) {
          appLogger.e(
            '[ScrcpyServer] Failed to connect after $maxAttempts attempts',
            e,
          );
          rethrow;
        }
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  /// Stops the scrcpy server.
  Future<void> stop() async {
    appLogger.i('[ScrcpyServer] Stopping for device: $deviceId');
    await _proxy.stop();
    await _socketSubscription?.cancel();
    await _socket?.close();
    _serverProcess?.kill();
    try {
      await adbClient.forwardRemove('tcp:$port', deviceId: deviceId);
    } catch (_) {}
    _parser.close();
  }
}
