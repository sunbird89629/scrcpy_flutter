import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_app/mcp_server_controller.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class _MockAdb implements ScrcpyAdb {
  @override
  Future<List<String>> getDevices() async => ['device1'];
  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      ProcessResult(0, 0, '', '');
  @override
  Future<void> forward(String local, String remote,
      {String? deviceId, bool noRebind = false}) async {}
  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {}
  @override
  Future<void> push(String localPath, String remotePath,
      {String? deviceId}) async {}
  @override
  Future<Uint8List> takeScreenshot(String deviceId) async => Uint8List(0);
  @override
  Future<Process> startProcess(List<String> arguments) =>
      throw UnimplementedError();
}

class _MockViewController extends ScrcpyViewController {
  _MockViewController() : super(adb: _MockAdb());
}

void main() {
  test('McpServerController — initial state is not running', () {
    final vc = _MockViewController();
    addTearDown(vc.dispose);
    final ctrl = McpServerController(
      session: vc,
      adb: _MockAdb(),
    );
    addTearDown(ctrl.dispose);

    expect(ctrl.isRunning, isFalse);
    expect(ctrl.serverUrl, isNull);
    expect(ctrl.errorMessage, isNull);
    expect(ctrl.port, 7070);
  });

  test('McpServerController — start sets isRunning and serverUrl', () async {
    final vc = _MockViewController();
    addTearDown(vc.dispose);
    final ctrl = McpServerController(
      session: vc,
      adb: _MockAdb(),
    );
    addTearDown(ctrl.dispose);
    addTearDown(() async => ctrl.stop());

    ctrl.port = 19818;
    await ctrl.start();

    expect(ctrl.isRunning, isTrue);
    expect(ctrl.serverUrl, 'http://localhost:19818/mcp');
    expect(ctrl.errorMessage, isNull);
  });

  test('McpServerController — stop clears state', () async {
    final vc = _MockViewController();
    addTearDown(vc.dispose);
    final ctrl = McpServerController(
      session: vc,
      adb: _MockAdb(),
    );
    addTearDown(ctrl.dispose);

    ctrl.port = 19819;
    await ctrl.start();
    await ctrl.stop();

    expect(ctrl.isRunning, isFalse);
    expect(ctrl.serverUrl, isNull);
  });
}
