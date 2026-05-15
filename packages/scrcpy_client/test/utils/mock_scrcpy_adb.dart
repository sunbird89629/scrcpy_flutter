import 'dart:io';
import 'dart:typed_data';
import 'package:scrcpy_client/scrcpy_client.dart';

class MockScrcpyAdb implements ScrcpyAdb {
  final List<List<String>> shellCalls = [];
  final List<(String, String)> forwardCalls = [];
  final List<(String, String)> pushCalls = [];
  final List<String> forwardRemoveCalls = [];
  final List<List<String>> startProcessCalls = [];

  bool shouldPushFail = false;
  bool shouldForwardFail = false;
  bool shouldStartProcessFail = false;

  @override
  Future<List<String>> getDevices() async => ['emulator-5554'];

  @override
  Future<ProcessResult> shell(
    List<String> args, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    shellCalls.add(args);
    return ProcessResult(0, 0, '', '');
  }

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {
    if (shouldForwardFail) throw Exception('Forward failed');
    forwardCalls.add((local, remote));
  }

  @override
  Future<void> push(String local, String remote, {String? deviceId}) async {
    if (shouldPushFail) throw Exception('Push failed');
    pushCalls.add((local, remote));
  }

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {
    forwardRemoveCalls.add(local);
  }

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async => Uint8List(0);

  @override
  Future<Process> startProcess(List<String> arguments) async {
    startProcessCalls.add(arguments);
    if (shouldStartProcessFail) throw Exception('startProcess failed');
    // Spawn a no-op process so callers can subscribe to streams.
    return Process.start('true', []);
  }
}
