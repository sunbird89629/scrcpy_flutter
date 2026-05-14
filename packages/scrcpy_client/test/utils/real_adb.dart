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
  Future<Uint8List> takeScreenshot(String deviceId) async =>
      adbTool.takeScreenshot(deviceId);

  @override
  Future<Process> startProcess(List<String> arguments) =>
      Process.start('adb', arguments);

  // Coordinates 540,1594 target the 名字 field on 1080×2340 Pixel devices.
  static const _contactNameFieldX = 540;
  static const _contactNameFieldY = 1594;

  Future<void> startContactPageForTest(String deviceId) async {
    await shell(
      [
        'am',
        'start',
        '-a',
        'android.intent.action.INSERT',
        '-t',
        'vnd.android.cursor.dir/contact'
      ],
      deviceId: deviceId,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    await shell(
      ['input', 'tap', '$_contactNameFieldX', '$_contactNameFieldY'],
      deviceId: deviceId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
