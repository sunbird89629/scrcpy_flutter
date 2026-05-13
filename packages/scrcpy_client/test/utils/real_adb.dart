import 'dart:io';
import 'dart:typed_data';

import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_client/src/scrcpy_adb.dart';

class RealAdb implements ScrcpyAdb {
  RealAdb();

  final adbTool = AdbClient();

  @override
  Future<List<String>> getDevices() => adbTool.getDevices();

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      adbTool.shell(arguments, deviceId: deviceId, timeout: timeout);

  @override
  Future<void> forward(String local, String remote,
          {String? deviceId, bool noRebind = false}) =>
      adbTool.forward(local, remote, deviceId: deviceId, noRebind: noRebind);

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) =>
      adbTool.forwardRemove(local, deviceId: deviceId);

  @override
  Future<void> push(String localPath, String remotePath, {String? deviceId}) =>
      adbTool.push(localPath, remotePath);

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async => Uint8List(0);

  @override
  Future<Process> startProcess(List<String> arguments) =>
      Process.start('adb', arguments);
}
