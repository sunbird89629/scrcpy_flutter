import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'utils/mock_scrcpy_adb.dart';

void main() {
  final mockJarBytes = Uint8List(0);

  group('AdbScrcpyDeviceProvisioner', () {
    late MockScrcpyAdb mockAdb;

    setUp(() {
      mockAdb = MockScrcpyAdb();
    });

    test('provision() pushes server JAR and starts process', () async {
      final provisioner = AdbScrcpyDeviceProvisioner(
        adb: mockAdb,
        deviceId: 'test-device',
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );
      // provision() will succeed through push/forward but fail on _connectAll
      // because no actual sockets are listening. For unit testing we just
      // call provision() directly.
      await provisioner.provision();

      // Verify startProcess was called with expected arguments
      expect(mockAdb.startProcessCalls, isNotEmpty);
      final args = mockAdb.startProcessCalls.first;
      expect(args, containsAllInOrder(['-s', 'test-device', 'shell']));
      expect(args, anyElement(contains('CLASSPATH=')));
      expect(args, anyElement(contains('scrcpy-server')));
      expect(args, anyElement(contains('com.genymobile.scrcpy.Server')));

      // Verify push was called
      expect(mockAdb.pushCalls, isNotEmpty);
      expect(mockAdb.pushCalls.first.$2, contains('scrcpy-server'));

      // Verify forward was set up
      expect(mockAdb.forwardCalls, isNotEmpty);
      expect(mockAdb.forwardCalls.first.$1, contains('tcp:'));
      expect(mockAdb.forwardCalls.first.$2, contains('localabstract:scrcpy'));

      await provisioner.depovision();
    });

    test('depovision() removes forward', () async {
      final provisioner = AdbScrcpyDeviceProvisioner(
        adb: mockAdb,
        deviceId: 'test-device',
        serverJarBytes: mockJarBytes,
        options: const ScrcpyServerOptions(),
      );
      await provisioner.provision();
      await provisioner.depovision();

      expect(mockAdb.forwardRemoveCalls, isNotEmpty);
      expect(mockAdb.forwardRemoveCalls.first, contains('tcp:'));
    });

    test('stores provided configuration', () {
      const opts = ScrcpyServerOptions(
        maxSize: 720,
        maxFps: 30,
        videoBitRate: 2000000,
        videoCodec: 'h265',
      );
      final provisioner = AdbScrcpyDeviceProvisioner(
        adb: mockAdb,
        deviceId: 'abc123',
        serverJarBytes: mockJarBytes,
        options: opts,
        port: 12345,
      );

      expect(provisioner.deviceId, 'abc123');
      expect(provisioner.port, 12345);
      expect(provisioner.options.maxSize, 720);
      expect(provisioner.options.videoCodec, 'h265');
      expect(provisioner.actualPort, 12345);
    });

    test('provision() forwards ScrcpyServerOptions to adb command', () async {
      const opts = ScrcpyServerOptions(
        maxSize: 720,
        maxFps: 15,
        videoBitRate: 1000000,
        videoCodec: 'h265',
      );
      final provisioner = AdbScrcpyDeviceProvisioner(
        adb: mockAdb,
        deviceId: 'test-device',
        serverJarBytes: mockJarBytes,
        options: opts,
      );
      await provisioner.provision();

      expect(mockAdb.startProcessCalls, isNotEmpty);
      final args = mockAdb.startProcessCalls.first;
      expect(args, anyElement('max_size=720'));
      expect(args, anyElement('max_fps=15'));
      expect(args, anyElement('video_bit_rate=1000000'));
      expect(args, anyElement('video_codec=h265'));

      await provisioner.depovision();
    });
  });
}
