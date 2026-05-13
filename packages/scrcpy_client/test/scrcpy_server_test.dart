import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'utils/mock_scrcpy_adb.dart';

void main() {
  final mockJarBytes = Uint8List(0);

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
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );

      expect(server.deviceId, 'device123');
      expect(server.port, 12345);
      server.stop();
    });

    test('uses default port when not specified', () {
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device123',
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );

      expect(server.port, 27183);
      server.stop();
    });

    test('supports multiple instances with different ports', () async {
      final server1 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device1',
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );

      final server2 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device2',
        port: 27184,
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );

      expect(server1.port, 27183);
      expect(server2.port, 27184);

      await server1.stop();
      await server2.stop();
    });

    test('adb client reference is stored correctly', () {
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device123',
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );

      expect(server.adb, mockAdb);
      server.stop();
    });
  });

  group('ScrcpyServer ADB Operations', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('start() delegates server process launch to adb.startProcess()',
        () async {
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'test-device',
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );
      // startProcess records args then returns a no-op process;
      // the next step (_connectAll) will fail because nothing is listening.
      await expectLater(server.start(), throwsA(isA<Exception>()));

      expect(mockAdb.startProcessCalls, isNotEmpty);
      final args = mockAdb.startProcessCalls.first;
      expect(args, containsAllInOrder(['-s', 'test-device', 'shell']));
      expect(args, anyElement(contains('CLASSPATH=')));
      expect(args, anyElement(contains('scrcpy-server')));
      expect(args, anyElement(contains('com.genymobile.scrcpy.Server')));
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
      final server1 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device1',
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );

      final server2 = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device2',
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );

      expect(server1.deviceId, 'device1');
      expect(server2.deviceId, 'device2');

      server1.stop();
      server2.stop();
    });
  });

  group('ScrcpyServer Configuration (options)', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('stores provided options', () {
      const opts = ScrcpyServerOptions(
        maxSize: 720,
        maxFps: 30,
        videoBitRate: 2000000,
        videoCodec: 'h265',
      );
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device123',
        serverJarBytes: mockJarBytes,
        options: opts,
      );
      expect(server.options.maxSize, 720);
      expect(server.options.maxFps, 30);
      expect(server.options.videoBitRate, 2000000);
      expect(server.options.videoCodec, 'h265');
      server.stop();
    });

    test('options defaults match ScrcpyServerOptions defaults', () {
      const opts = ScrcpyServerOptions();
      final server = ScrcpyServer(
        adb: mockAdb,
        deviceId: 'device123',
        serverJarBytes: mockJarBytes,
        options: opts,
      );
      expect(server.options.maxSize, 1024);
      expect(server.options.maxFps, 60);
      expect(server.options.videoBitRate, 6000000);
      expect(server.options.videoCodec, 'h264');
      server.stop();
    });
  });

  group('ScrcpyServerOptions', () {
    test('has correct defaults', () {
      const opts = ScrcpyServerOptions();
      expect(opts.maxSize, 1024);
      expect(opts.maxFps, 60);
      expect(opts.videoBitRate, 6000000);
      expect(opts.videoCodec, 'h264');
    });

    test('accepts custom values', () {
      const opts = ScrcpyServerOptions(
        maxSize: 720,
        maxFps: 30,
        videoBitRate: 2000000,
        videoCodec: 'h265',
      );
      expect(opts.maxSize, 720);
      expect(opts.maxFps, 30);
      expect(opts.videoBitRate, 2000000);
      expect(opts.videoCodec, 'h265');
    });

    test('supports value equality', () {
      const a = ScrcpyServerOptions(maxSize: 720);
      const b = ScrcpyServerOptions(maxSize: 720);
      final c = ScrcpyServerOptions(maxSize: 720);
      // Equal instances
      expect(a, equals(b));
      expect(a, equals(c));
      // Not equal to different values
      const d = ScrcpyServerOptions(maxSize: 1080);
      expect(a, isNot(equals(d)));
      // hashCode is consistent with ==
      expect(a.hashCode, equals(b.hashCode));
      expect(a.hashCode, equals(c.hashCode));
    });

    test('toString includes all fields', () {
      const opts = ScrcpyServerOptions(maxSize: 720, maxFps: 30, videoBitRate: 2000000, videoCodec: 'h265');
      final s = opts.toString();
      expect(s, contains('720'));
      expect(s, contains('30'));
      expect(s, contains('2000000'));
      expect(s, contains('h265'));
    });
  });

  group('ScrcpySessionImpl options threading', () {
    test('start() accepts custom options and throws on failure', () async {
      final mockAdb = MockScrcpyAdb();
      mockAdb.shouldPushFail = true;
      final session = ScrcpySessionImpl(
        adb: mockAdb,
        serverJarBytes: Uint8List(0),
      );

      const opts = ScrcpyServerOptions(maxSize: 720, maxFps: 30);
      // options forwarding to ScrcpyServer._options is covered by the
      // 'ScrcpyServer Configuration (options)' group above.
      // This test verifies the parameter signature and error-path cleanup.
      await expectLater(
        () => session.start('test-device', options: opts),
        throwsException,
      );
      // After failure, session must be in a clean state (not pending, no server assigned)
      expect(session.server, isNull);
      expect(session.isActive, isFalse);
    });
  });
}
