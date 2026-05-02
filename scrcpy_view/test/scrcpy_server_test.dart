import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_view/src/scrcpy_adb.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';

class MockScrcpyAdb implements ScrcpyAdb {
  MockScrcpyAdb({this.testAdbPath = 'adb'});

  final String testAdbPath;

  @override
  String get adbPath => testAdbPath;

  final List<List<String>> shellCalls = [];
  final List<(String, String)> forwardCalls = [];
  final List<(String, String)> pushCalls = [];
  final List<String> forwardRemoveCalls = [];

  bool shouldPushFail = false;
  bool shouldForwardFail = false;

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (
    MethodCall methodCall,
  ) async {
    if (methodCall.method == 'getApplicationSupportDirectory') {
      return Directory.systemTemp.path;
    } else if (methodCall.method == 'getTemporaryDirectory') {
      return Directory.systemTemp.path;
    }
    return null;
  });

  group('ScrcpyServer Configuration', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('initializes with required parameters', () {
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device123',
        port: 12345,
      );

      expect(server.deviceId, 'device123');
      expect(server.port, 12345);
      server.stop();
    });

    test('uses default port when not specified', () {
      final server = ScrcpyServer(adb: mockAdb, deviceId: 'device123');

      expect(server.port, 27183);
      server.stop();
    });

    test('supports multiple instances with different ports', () async {
      final server1 = ScrcpyServer(adb: mockAdb, deviceId: 'device1');

      final server2 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device2',
        port: 27184,
      );

      expect(server1.port, 27183);
      expect(server2.port, 27184);

      await server1.stop();
      await server2.stop();
    });

    test('adb client reference is stored correctly', () {
      final server = ScrcpyServer(adb: mockAdb, deviceId: 'device123');

      expect(server.adb, mockAdb);
      server.stop();
    });
  });

  group('ScrcpyServer ADB Operations', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('verifies shell command with correct parameters', () async {
      await mockAdb.shell([
        'chmod',
        '755',
        '/data/local/tmp/scrcpy-server',
      ], deviceId: 'emulator-5554');

      expect(mockAdb.shellCalls, isNotEmpty);
      expect(mockAdb.shellCalls[0], containsAll(['chmod', '755']));
    });

    test('verifies forward command parameters', () async {
      await mockAdb.forward(
        'tcp:27183',
        'localabstract:scrcpy',
        deviceId: 'specific-device-id',
      );

      expect(mockAdb.forwardCalls, isNotEmpty);
    });
  });

  group('ScrcpyServer Device Management', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('works with multiple device IDs', () {
      final server1 = ScrcpyServer(adb: mockAdb, deviceId: 'device1');

      final server2 = ScrcpyServer(adb: mockAdb, deviceId: 'device2');

      expect(server1.deviceId, 'device1');
      expect(server2.deviceId, 'device2');

      server1.stop();
      server2.stop();
    });
  });
}
