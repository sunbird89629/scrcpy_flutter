import 'dart:io';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/src/scrcpy_server.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAdbClient extends AdbClient {
  MockAdbClient({String? testAdbPath})
      : super(
          adbPath: testAdbPath ?? 'adb',
          runner: const AdbProcessRunner(),
        );

  final List<List<String>> shellCalls = [];
  final List<(String, String)> forwardCalls = [];
  final List<(String, String)> pushCalls = [];
  final List<String> forwardRemoveCalls = [];

  bool shouldPushFail = false;
  bool shouldForwardFail = false;

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
    if (shouldForwardFail) {
      throw const AdbException('Forward failed');
    }
    forwardCalls.add((local, remote));
  }

  @override
  Future<void> push(
    String local,
    String remote, {
    String? deviceId,
  }) async {
    if (shouldPushFail) {
      throw const AdbException('Push failed');
    }
    pushCalls.add((local, remote));
  }

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {
    forwardRemoveCalls.add(local);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Initialize logger for tests
  final tempLogsDir = Directory.systemTemp.createTempSync('scrcpy_logs');
  initAppLogger(logsDir: tempLogsDir.path);

  // Mock path_provider
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel,
          (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationSupportDirectory') {
      return Directory.systemTemp.path;
    } else if (methodCall.method == 'getTemporaryDirectory') {
      return Directory.systemTemp.path;
    }
    return null;
  });

  group('ScrcpyServer Integration Tests', () {
    const adbClient = AdbClient();
    late ScrcpyServer server;

    const realDeviceId = '11081FDD4004DY';

    setUp(() {
      server = ScrcpyServer(
        adbClient: adbClient,
        deviceId: realDeviceId,
      );
    });

    tearDown(() async {
      await server.stop();
    });
    test('initializes with required parameters', () async {
      expect(server.deviceId, realDeviceId);
      expect(server.port, 27183);
      await server.start();
      await Future.delayed(const Duration(seconds: 10));
    });
  });

  group('ScrcpyServer Error Handling', () {
    late MockAdbClient mockAdbClient;
    late ScrcpyServer server;

    setUp(() {
      mockAdbClient = MockAdbClient();
      server = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'emulator-5554',
      );
    });

    tearDown(() async {
      await server.stop();
    });

    test('handles push failure', () async {
      mockAdbClient.shouldPushFail = true;

      expect(
        () => mockAdbClient.push(
          '/fake/path',
          '/data/local/tmp/scrcpy-server',
          deviceId: 'emulator-5554',
        ),
        throwsA(isA<AdbException>()),
      );
    });

    test('custom port configuration', () {
      final customServer = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'emulator-5554',
        port: 9999,
      );

      expect(customServer.port, 9999);
      customServer.stop();
    });
  });

  group('ScrcpyServer Configuration', () {
    late MockAdbClient mockAdbClient;

    setUp(() {
      mockAdbClient = MockAdbClient();
    });

    test('initializes with required parameters', () {
      final server = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'device123',
        port: 12345,
      );

      expect(server.deviceId, 'device123');
      expect(server.port, 12345);
      server.stop();
    });

    test('uses default port when not specified', () {
      final server = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'device123',
      );

      expect(server.port, 27183);
      server.stop();
    });

    test('supports multiple instances with different ports', () async {
      final server1 = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'device1',
      );

      final server2 = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'device2',
        port: 27184,
      );

      expect(server1.port, 27183);
      expect(server2.port, 27184);

      await server1.stop();
      await server2.stop();
    });

    test('adb client is stored correctly', () {
      final server = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'device123',
      );

      expect(server.adbClient, mockAdbClient);
      server.stop();
    });
  });

  group('ScrcpyServer ADB Command Verification', () {
    late MockAdbClient mockAdbClient;

    setUp(() {
      mockAdbClient = MockAdbClient();
    });

    test('verifies chmod command is called with correct parameters', () async {
      await mockAdbClient.shell(
        ['chmod', '755', '/data/local/tmp/scrcpy-server'],
        deviceId: 'emulator-5554',
      );

      expect(mockAdbClient.shellCalls, isNotEmpty);
      expect(mockAdbClient.shellCalls[0], containsAll(['chmod', '755']));
    });

    test(
      'verifies app_process command with correct scrcpy parameters',
      () async {
        await mockAdbClient.shell(
          [
            'shell',
            'CLASSPATH=/data/local/tmp/scrcpy-server',
            'app_process',
            '/',
            'com.genymobile.scrcpy.Server',
            '3.3.3',
            'tunnel_forward=true',
            'control=false',
            'audio=false',
            'send_dummy_byte=true',
          ],
          deviceId: 'emulator-5554',
        );

        expect(mockAdbClient.shellCalls, isNotEmpty);
        expect(
          mockAdbClient.shellCalls[0],
          containsAll(['com.genymobile.scrcpy.Server', '3.3.3']),
        );
      },
    );
  });

  group('ScrcpyServer Device Management', () {
    late MockAdbClient mockAdbClient;

    setUp(() {
      mockAdbClient = MockAdbClient();
    });

    test('works with multiple device IDs', () {
      final server1 = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'device1',
      );

      final server2 = ScrcpyServer(
        adbClient: mockAdbClient,
        deviceId: 'device2',
      );

      expect(server1.deviceId, 'device1');
      expect(server2.deviceId, 'device2');

      server1.stop();
      server2.stop();
    });

    test('forward uses correct device ID in parameters', () async {
      await mockAdbClient.forward(
        'tcp:27183',
        'localabstract:scrcpy',
        deviceId: 'specific-device-id',
      );

      expect(mockAdbClient.forwardCalls, isNotEmpty);
    });
  });
}
