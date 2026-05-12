import 'dart:io';
import 'dart:typed_data';

import 'package:adb_tools/adb_tools.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class SafeAdbClient implements ScrcpyAdb {
  SafeAdbClient({AdbClient? client}) : _client = client ?? const AdbClient();

  final AdbClient _client;

  @override
  String get adbPath => _client.adbPath;

  @override
  Future<List<String>> getDevices() => _client.getDevices();

  @override
  Future<ProcessResult> shell(
    List<String> args, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await _client.shell(args, deviceId: deviceId, timeout: timeout);
    } catch (e) {
      final cmd = args.join(' ');
      if (cmd.contains('pkill')) {
        debugPrint('SafeAdbClient: Ignoring pkill failure: $e');
        return ProcessResult(0, 0, '', '');
      }
      rethrow;
    }
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
      throw ProcessException(
        adbPath,
        ['-s', deviceId, 'exec-out', 'screencap', '-p'],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return Uint8List.fromList(result.stdout as List<int>);
  }
}
