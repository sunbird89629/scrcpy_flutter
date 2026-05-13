import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'utils/mock_device_provisioner.dart';
import 'utils/mock_scrcpy_adb.dart';

void main() {
  group('ScrcpyServer Configuration', () {
    late MockDeviceProvisioner provisioner;

    setUp(() {
      provisioner = MockDeviceProvisioner();
    });

    test('initializes with required parameters', () {
      final server = ScrcpyServer(provisioner: provisioner);
      expect(server.deviceId, 'test-device');
      expect(server.port, 27183);
      server.stop();
    });

    test('uses provisioner port', () {
      final p = MockDeviceProvisioner(port: 12345);
      final server = ScrcpyServer(provisioner: p);
      expect(server.port, 12345);
      server.stop();
    });

    test('supports multiple instances with different provisioners', () async {
      final p1 = MockDeviceProvisioner(deviceId: 'device1');
      final server1 = ScrcpyServer(provisioner: p1);

      final p2 = MockDeviceProvisioner(deviceId: 'device2', port: 27184);
      final server2 = ScrcpyServer(provisioner: p2);

      expect(server1.deviceId, 'device1');
      expect(server1.port, 27183);
      expect(server2.deviceId, 'device2');
      expect(server2.port, 27184);

      await server1.stop();
      await server2.stop();
    });

    test('start() delegates to provisioner.provision()', () async {
      provisioner.shouldProvisionFail = true;
      final server = ScrcpyServer(provisioner: provisioner);
      await expectLater(server.start(), throwsA(isA<Exception>()));
      expect(provisioner.provisionCalled, isTrue);
    });

    test('stop() delegates to provisioner.depovision()', () async {
      final server = ScrcpyServer(provisioner: provisioner);
      await server.stop();
      expect(provisioner.depovisionCalled, isTrue);
    });
  });

  group('ScrcpyServer Device Management', () {
    test('works with multiple device IDs', () {
      final p1 = MockDeviceProvisioner(deviceId: 'device1');
      final server1 = ScrcpyServer(provisioner: p1);

      final p2 = MockDeviceProvisioner(deviceId: 'device2');
      final server2 = ScrcpyServer(provisioner: p2);

      expect(server1.deviceId, 'device1');
      expect(server2.deviceId, 'device2');

      server1.stop();
      server2.stop();
    });
  });

  group('ScrcpyServer Configuration (options)', () {
    test('stores provided options', () {
      const opts = ScrcpyServerOptions(
        maxSize: 720,
        maxFps: 30,
        videoBitRate: 2000000,
        videoCodec: 'h265',
      );
      final provisioner = MockDeviceProvisioner(options: opts);
      final server = ScrcpyServer(provisioner: provisioner);
      expect(server.options.maxSize, 720);
      expect(server.options.maxFps, 30);
      expect(server.options.videoBitRate, 2000000);
      expect(server.options.videoCodec, 'h265');
      server.stop();
    });

    test('options defaults match ScrcpyServerOptions defaults', () {
      final provisioner = MockDeviceProvisioner();
      final server = ScrcpyServer(provisioner: provisioner);
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
      expect(a, equals(b));
      expect(a, equals(c));
      const d = ScrcpyServerOptions(maxSize: 1080);
      expect(a, isNot(equals(d)));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.hashCode, equals(c.hashCode));
    });

    test('toString includes all fields', () {
      const opts = ScrcpyServerOptions(
        maxSize: 720,
        maxFps: 30,
        videoBitRate: 2000000,
        videoCodec: 'h265',
      );
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
      await expectLater(
        () => session.start('test-device', options: opts),
        throwsException,
      );
      expect(session.server, isNull);
      expect(session.isActive, isFalse);
    });
  });
}
