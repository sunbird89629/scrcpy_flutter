import 'dart:io';
import 'dart:typed_data';
import 'package:scrcpy_client/src/scrcpy_adb.dart';

class NoOpAdb implements ScrcpyAdb {
  const NoOpAdb();

  @override
  Future<List<String>> getDevices() async => [];

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
  Future<Uint8List> takeScreenshot(String deviceId) async => Uint8List(0);

  @override
  Future<Process> startProcess(List<String> arguments) =>
      throw UnimplementedError('NoOpAdb.startProcess');
}
