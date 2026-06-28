import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_mcp/scrcpy_mcp.dart';

class FakeEvalActionRunner {
  final actions = <DoAction>[];

  Future<String> call(PhoneAction action) async {
    if (action is DoAction) {
      actions.add(action);
      return 'ran ${action.action}';
    }
    return '(finish)';
  }
}

class FakeScrcpyMcpAdb implements ScrcpyMcpAdb {
  @override
  Future<List<String>> getDevices() async => ['device1'];

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async => ProcessResult(0, 0, '', '');

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {}

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {}

  @override
  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) async {}

  @override
  Future<Process> startProcess(List<String> arguments) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async =>
      Uint8List.fromList([1]);

  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> pullFile(
    String deviceId,
    String remotePath,
    String localPath,
  ) async {}

  @override
  Future<void> removeFile(String deviceId, String remotePath) async {}
}
