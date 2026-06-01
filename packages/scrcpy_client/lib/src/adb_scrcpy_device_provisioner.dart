import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:scrcpy_client/src/scrcpy_adb.dart';
import 'package:scrcpy_client/src/scrcpy_device_provisioner.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_server.dart';
import 'package:scrcpy_client/src/scrcpy_server_options.dart';

/// ADB-based implementation of [ScrcpyDeviceProvisioner].
class AdbScrcpyDeviceProvisioner implements ScrcpyDeviceProvisioner {
  AdbScrcpyDeviceProvisioner({
    required this.adb,
    required this.deviceId,
    required Uint8List serverJarBytes,
    required this.options,
    this.port = 27183,
    ScrcpyLogger? logger,
  }) : _serverJarBytes = serverJarBytes,
       _log = logger ?? const NoOpScrcpyLogger();

  final ScrcpyAdb adb;

  @override
  final String deviceId;

  @override
  final int port;

  @override
  final ScrcpyServerOptions options;

  final Uint8List _serverJarBytes;
  final ScrcpyLogger _log;

  Process? _serverProcess;
  int? _actualPort;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _isProvisioned = false;

  String get _remoteJarPath =>
      '/data/local/tmp/scrcpy-server-v${ScrcpyServer.serverVersion}.jar';

  @override
  int get actualPort => _actualPort ?? port;

  @override
  Future<void> provision() async {
    if (_isProvisioned) return;
    try {
      await _pushServer();
      await _setupForwardWithRetry();
      await _runServer();
      _isProvisioned = true;
    } catch (_) {
      await depovision();
      rethrow;
    }
  }

  @override
  Future<void> depovision() async {
    _isProvisioned = false;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    _serverProcess?.kill();
    _serverProcess = null;

    final cleanupPort = _actualPort ?? port;
    try {
      await adb.forwardRemove('tcp:$cleanupPort', deviceId: deviceId);
    } catch (_) {}
  }

  Future<void> _pushServer() async {
    const version = ScrcpyServer.serverVersion;

    try {
      _log.debug(
        '[AdbScrcpyDeviceProvisioner] Writing server JAR to temp file',
      );
      final tempDir = Directory.systemTemp;
      final localTempFile = File(
        p.join(tempDir.path, 'scrcpy-server-v$version.jar'),
      );
      await localTempFile.writeAsBytes(_serverJarBytes, flush: true);
      _log.debug(
        '[AdbScrcpyDeviceProvisioner] Pushing server to device: $_remoteJarPath',
      );
      await adb.push(localTempFile.path, _remoteJarPath, deviceId: deviceId);
      await localTempFile.delete();
    } on Exception catch (e, st) {
      _log.error(
        '[AdbScrcpyDeviceProvisioner] Failed to prepare server on device',
        e,
        st,
      );
      rethrow;
    }
  }

  static const _scid = '12345678';
  static const _socketName = 'scrcpy_$_scid';

  Future<void> _setupForwardWithRetry() async {
    const maxRetries = 10;
    var currentPort = port;

    for (var i = 0; i < maxRetries; i++) {
      try {
        _log.debug(
          '[AdbScrcpyDeviceProvisioner] Setting up forward: tcp:$currentPort'
          ' -> localabstract:$_socketName',
        );
        try {
          await adb.forwardRemove('tcp:$currentPort', deviceId: deviceId);
        } catch (_) {}
        await adb.forward(
          'tcp:$currentPort',
          'localabstract:$_socketName',
          deviceId: deviceId,
        );
        _actualPort = currentPort;
        return;
      } on Exception catch (e) {
        _log.warn(
          '[AdbScrcpyDeviceProvisioner] Failed to forward on port $currentPort, retrying...',
          e,
        );
        currentPort++;
      }
    }
    throw Exception(
      'Failed to setup port forwarding after $maxRetries attempts',
    );
  }

  Future<void> _runServer() async {
    const version = ScrcpyServer.serverVersion;

    try {
      await adb.shell(['pkill', '-f', 'scrcpy-server-v'], deviceId: deviceId);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final args = [
      if (deviceId.isNotEmpty) ...['-s', deviceId],
      'shell',
      'CLASSPATH=$_remoteJarPath',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      version,
      'scid=$_scid',
      'tunnel_forward=true',
      'video_codec=${options.videoCodec}',
      'audio=false',
      'control=true',
      'cleanup=true',
      'max_size=${options.maxSize}',
      'max_fps=${options.maxFps}',
      'video_bit_rate=${options.videoBitRate}',
      'list_encoders=false',
      'list_displays=false',
      'send_dummy_byte=true',
      'video_codec_options=i-frame-interval=1,latency=1',
      'power_on=true',
    ];

    _log.debug('[AdbScrcpyDeviceProvisioner] Executing: adb ${args.join(' ')}');
    _serverProcess = await adb.startProcess(args);

    _stdoutSubscription = _serverProcess!.stdout.transform(utf8.decoder).listen(
      (line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _log.debug('[AdbScrcpyDeviceProvisioner:stdout] $trimmed');
        }
      },
    );

    _stderrSubscription = _serverProcess!.stderr.transform(utf8.decoder).listen(
      (line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        if (trimmed.contains('ERROR') || trimmed.contains('Exception')) {
          _log.error('[AdbScrcpyDeviceProvisioner:stderr] $trimmed');
        } else {
          _log.warn('[AdbScrcpyDeviceProvisioner:stderr] $trimmed');
        }
      },
    );

    unawaited(
      _serverProcess!.exitCode.then((code) {
        _log.warn(
          '[AdbScrcpyDeviceProvisioner] server process exited with code $code',
        );
      }),
    );

    await Future<void>.delayed(const Duration(seconds: 1));
  }
}
