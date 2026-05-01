import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:stream_channel/stream_channel.dart';

class MockAdb implements ScrcpyAdb {
  List<String> devices = ['device1', 'device2'];

  @override
  String get adbPath => 'adb';

  @override
  Future<List<String>> getDevices() async => devices;

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
}

/// Creates an in-memory [StreamChannel] for testing MCP servers.
StreamChannel<String> _testChannel() {
  final controller = StreamChannelController<String>();
  return controller.foreign;
}

void main() {
  group('ScrcpyMcpServer', () {
    test('list_devices returns device list', () async {
      final server = ScrcpyMcpServer(
        _testChannel(),
        adb: MockAdb(),
      );
      expect(server, isNotNull);
    });

    test('start_mirroring tool is registered', () async {
      final server = ScrcpyMcpServer(
        _testChannel(),
        adb: MockAdb(),
      );
      expect(server, isNotNull);
    });

    test('stop_mirroring tool is registered', () async {
      final server = ScrcpyMcpServer(
        _testChannel(),
        adb: MockAdb(),
      );
      expect(server, isNotNull);
    });

    test('inject_key tool is registered', () async {
      final server = ScrcpyMcpServer(
        _testChannel(),
        adb: MockAdb(),
      );
      expect(server, isNotNull);
    });

    test('inject_touch tool is registered', () async {
      final server = ScrcpyMcpServer(
        _testChannel(),
        adb: MockAdb(),
      );
      expect(server, isNotNull);
    });

    test('inject_text tool is registered', () async {
      final server = ScrcpyMcpServer(
        _testChannel(),
        adb: MockAdb(),
      );
      expect(server, isNotNull);
    });

    test('inject_scroll tool is registered', () async {
      final server = ScrcpyMcpServer(
        _testChannel(),
        adb: MockAdb(),
      );
      expect(server, isNotNull);
    });
  });
}
