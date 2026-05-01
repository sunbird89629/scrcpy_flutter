import 'dart:io';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_logger/autoglm_logger.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// Bridges the MCP package's ADB client to the scrcpy package boundary.
class ScrcpyMcpAdb implements ScrcpyAdb {
  /// Creates an ADB bridge around [AdbClient].
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
}

/// Bridges MCP scrcpy logs to the shared application logger.
class ScrcpyMcpLogger implements ScrcpyLogger {
  /// Creates a logger bridge around the application logger.
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
