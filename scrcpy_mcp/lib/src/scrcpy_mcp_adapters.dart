import 'dart:io';
import 'dart:typed_data';

import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

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

/// Shared adapter bridging [AdbClient] to the [ScrcpyAdb] interface.
class ScrcpyAdbAdapter implements ScrcpyAdb {
  const ScrcpyAdbAdapter(this._client);

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
  Future<Uint8List> takeScreenshot(String deviceId) {
    return _client.takeScreenshot(deviceId);
  }
}

/// Extends [ScrcpyAdbAdapter] with screen recording operations for MCP.
class ScrcpyMcpAdb extends ScrcpyAdbAdapter implements RecordingAdb {
  const ScrcpyMcpAdb(super._client);

  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    final process = await Process.start(adbPath, [
      '-s',
      deviceId,
      'shell',
      'screenrecord',
      '--bit-rate',
      '$bitrate',
      '--time-limit',
      '$maxTime',
      remotePath,
    ]);
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
