import 'dart:io';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// Adapts [AdbClient] to the [ScrcpyAdb] interface.
class AdbClientAdapter implements ScrcpyAdb {
  /// Creates an adapter wrapping [client].
  AdbClientAdapter(this._client);

  /// Creates an adapter with a default [AdbClient] using [adbPath].
  AdbClientAdapter.withPath({String adbPath = 'adb'})
    : _client = AdbClient(adbPath: adbPath);

  final AdbClient _client;

  @override
  String get adbPath => _client.adbPath;

  @override
  Future<List<String>> getDevices() async => _client.listDevices();

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return _client.shell(arguments, deviceId: deviceId, timeout: timeout);
  }

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {
    return _client.forward(
      local,
      remote,
      deviceId: deviceId,
      noRebind: noRebind,
    );
  }

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {
    return _client.forwardRemove(local, deviceId: deviceId);
  }

  @override
  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) async {
    return _client.push(localPath, remotePath, deviceId: deviceId);
  }
}
