import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

  /// The preferred local port to forward to the scrcpy server.
  final int port;

  /// The actual port being used after dynamic selection.
  int? _actualPort;

  final ScrcpyProxyServer _proxy;
  final ScrcpyStreamParser _parser;

  int? _scid;
  Process? _serverProcess;
  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;

  /// The URL for the media player to connect to.
  String get proxyUrl => _proxy.proxyUrl;

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
    appLogger.i('[ScrcpyServer] Starting for device: $deviceId');

    // 1. Prepare the server binary on the device
    await _pushServer();

    // 2. Pick a random scid so the abstract socket name is unique per run
    //    (scrcpy server parses `scid=` as HEX and binds `scrcpy_%08x`).
    _scid = Random.secure().nextInt(0x7FFFFFFF);
    final scidHex = _scid!.toRadixString(16).padLeft(8, '0');
    final socketName = 'scrcpy_$scidHex';

    // 3. Setup port forwarding with retry logic for port conflicts
    await _setupForwardWithRetry(socketName);

    // 4. Run the server process
    await _runServer(scidHex);

    // 5. Subscribe the proxy BEFORE any data flows so SPS/PPS isn't missed.
    await _proxy.start(_parser.packets);
    appLogger.i('[ScrcpyServer] Proxy Media URL: ${_proxy.proxyUrl}');

    // 6. Connect to the forwarded port (retries while server is warming up).
    await _connect();
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
      'scid=$scidHex',
      'tunnel_forward=true',
      'video_codec=h264', // Force H264
      'audio=false',
      'control=false',
      'cleanup=true',
      'list_encoders=false',
      'list_displays=false',
      'send_dummy_byte=true',
      // Low-latency MediaCodec config:
      //   latency=1          MediaCodec low-latency mode (API 30+)
      //   priority=0         realtime thread priority
      //   operating-rate=max  hint the encoder to run full throttle
      //   i-frame-interval=1  quick recovery for new viewers
      // ignore: lines_longer_than_80_chars
      'video_codec_options=i-frame-interval=1,latency=1,priority=0,operating-rate=65535',
      'power_on=true', // Ensure screen is on
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

  Future<void> _connect() async {
    const maxAttempts = 30;
    const probeTimeout = Duration(seconds: 2);
    const retryDelay = Duration(milliseconds: 500);

    final connectPort = _actualPort ?? port;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      Socket? socket;
      StreamSubscription<Uint8List>? sub;
      try {
        appLogger.d(
          '[ScrcpyServer] Connection attempt $attempt/$maxAttempts to '
          'localhost:$connectPort',
        );
        socket = await Socket.connect('localhost', connectPort);

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
            '[ScrcpyServer] Attempt $attempt: no dummy byte received, retrying…',
          );
          await sub.cancel();
          await socket.close();
          await Future<void>.delayed(retryDelay);
          continue;
        }

        appLogger.i(
          '[ScrcpyServer] Tunnel dummy byte received, sending bootstrap (scid: $_scid)',
        );

        // scrcpy 3.0 bootstrap: scid (4 bytes) + tunnel_forward (1 byte)
        final bootstrap = ByteData(5);
        bootstrap.setInt32(0, _scid!);
        bootstrap.setUint8(4, 1); // 1 = tunnel_forward=true
        socket.add(bootstrap.buffer.asUint8List());
        await socket.flush();

        var totalBytes = 0;
        var logCountdown = 5;
        sub
          ..onData((data) {
            totalBytes += data.length;
            if (logCountdown > 0) {
              appLogger.d(
                '[ScrcpyServer] onData chunk=${data.length} '
                'total=$totalBytes',
              );
              logCountdown -= 1;
            }
            _parser.feed(Uint8List.fromList(data));
          })
          ..onDone(
            () => appLogger.w(
              '[ScrcpyServer] Socket closed (totalBytes=$totalBytes)',
            ),
          )
          ..onError(
            (Object e, StackTrace st) =>
                appLogger.e('[ScrcpyServer] Socket error', e, st),
          );

        // Feed initial bytes AFTER dummy byte to parser if they contain anything beyond dummy
        if (first.length > 1) {
          _parser.feed(Uint8List.fromList(first.sublist(1)));
        }

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

    final cleanupPort = _actualPort ?? port;
    try {
      await adbClient.forwardRemove('tcp:$cleanupPort', deviceId: deviceId);
    } catch (_) {}
    _parser.close();
  }
}
