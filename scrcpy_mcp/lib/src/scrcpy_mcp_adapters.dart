import 'dart:io';
import 'dart:typed_data';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_logger/autoglm_logger.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

import 'recording_adb.dart';
import 'recording_controller.dart';

/// Wraps [dart:io Process] to expose only what [RecordingController] needs.
class _RealProcess implements RecordingProcess {
  _RealProcess(this._process);
  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}

/// Bridges the MCP package's ADB client to the scrcpy package boundary.
class ScrcpyMcpAdb implements ScrcpyAdb, RecordingAdb {
  const ScrcpyMcpAdb(this._client);

  final AdbClient _client;

  @override
  String get adbPath => _client.adbPath;

  @override
  Future<List<String>> getDevices() => _client.getDevices();

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _client.shell(arguments, deviceId: deviceId, timeout: timeout);
  }

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) {
    return _client.forward(
      local,
      remote,
      deviceId: deviceId,
      noRebind: noRebind,
    );
  }

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) {
    return _client.forwardRemove(local, deviceId: deviceId);
  }

  @override
  Future<void> push(String localPath, String remotePath, {String? deviceId}) {
    return _client.push(localPath, remotePath, deviceId: deviceId);
  }

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async {
    final result = await Process.run(
      adbPath,
      ['-s', deviceId, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) {
      throw Exception(
        'screencap failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
    return Uint8List.fromList(result.stdout as List<int>);
  }

  // ── RecordingAdb ──────────────────────────────────────────────────────────

  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    final process = await Process.start(adbPath, [
      '-s', deviceId, 'shell', 'screenrecord',
      '--bit-rate', '$bitrate',
      '--time-limit', '$maxTime',
      remotePath,
    ]);
    // Drain to prevent pipe backpressure from blocking the recording process.
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    return _RealProcess(process);
  }

  @override
  Future<void> pullFile(
    String deviceId,
    String remotePath,
    String localPath,
  ) async {
    final result = await Process.run(
      adbPath,
      ['-s', deviceId, 'pull', remotePath, localPath],
    );
    if (result.exitCode != 0) {
      throw Exception(
        'adb pull failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
  }

  @override
  Future<void> removeFile(String deviceId, String remotePath) async {
    await Process.run(
      adbPath,
      ['-s', deviceId, 'shell', 'rm', '-f', remotePath],
    );
  }
}

/// Bridges MCP scrcpy logs to the shared application logger.
class ScrcpyMcpLogger implements ScrcpyLogger {
  const ScrcpyMcpLogger();

  @override
  void debug(String message) => appLogger.d(message);

  @override
  void info(String message) => appLogger.i(message);

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    appLogger.w(message, error, stack);
  }

  @override
  void error(String message, [Object? error, StackTrace? stack]) {
    appLogger.e(message, error, stack);
  }
}
