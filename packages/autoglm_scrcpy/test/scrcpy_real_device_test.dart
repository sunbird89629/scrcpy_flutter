import 'dart:async';
import 'dart:io';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  // Ensure we can use MethodChannels and Assets
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize logger for tests
  final tempLogsDir = Directory.systemTemp.createTempSync('scrcpy_logs');
  initAppLogger(logsDir: tempLogsDir.path);

  // Mock path_provider for getApplicationSupportDirectory and getTemporaryDirectory
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel,
          (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationSupportDirectory' ||
        methodCall.method == 'getTemporaryDirectory') {
      final tempDir = Directory.systemTemp.createTempSync('scrcpy_test_');
      return tempDir.path;
    }
    return null;
  });

  group('Scrcpy Real Device Integration Test', () {
    const adbClient = AdbClient();
    late String deviceId;
    ScrcpyServer? server;

    setUpAll(() async {
      final devices = await adbClient.devices();
      if (devices.isEmpty) {
        fail('No devices connected. Please connect an Android device via USB.');
      }
      deviceId = devices.first;
      print('Using device: $deviceId');
    });

    tearDown(() async {
      await server?.stop();
    });

    test(
      'Receives video packets from the device',
      () async {
        server = ScrcpyServer(
          adbClient: adbClient,
          deviceId: deviceId,
        );

        print('Starting ScrcpyServer...');
        await server!.start();

        final videoPackets = <ScrcpyPacket>[];
        final configPackets = <ScrcpyPacket>[];
        final completer = Completer<void>();

        final subscription = server!.packets.listen((packet) {
          debugPrint('packet:${packet.data.length}');
          if (packet.type == ScrcpyPacketType.video) {
            videoPackets.add(packet);
            if (videoPackets.isNotEmpty && configPackets.isNotEmpty) {
              if (!completer.isCompleted) {
                completer.complete();
              }
            }
          } else if (packet.type == ScrcpyPacketType.configuration) {
            configPackets.add(packet);
          }
        });

        print('Waiting for video packets (timeout 20s)...');

        try {
          await completer.future.timeout(const Duration(seconds: 20));
        } on TimeoutException {
          print(
            'Timeout reached. Received ${videoPackets.length} video packets and ${configPackets.length} config packets.',
          );
          if (configPackets.isEmpty) {
            fail('Did not receive any configuration packets (SPS/PPS).');
          }
          if (videoPackets.isEmpty) {
            fail('Did not receive any video packets.');
          }
        } finally {
          await subscription.cancel();
        }

        print('Successfully received ${videoPackets.length} video packets.');
        expect(
          configPackets,
          isNotEmpty,
          reason: 'Should receive at least one config packet',
        );
        expect(
          videoPackets.length,
          greaterThanOrEqualTo(1),
          reason: 'Should receive at least one video packet',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('sends touch and key control messages without error', () async {
      server = ScrcpyServer(
        adbClient: adbClient,
        deviceId: deviceId,
      );

      print('Starting ScrcpyServer for control test...');
      await server!.start();

      // Wait for control socket to be established
      await Future<void>.delayed(const Duration(seconds: 2));

      // Send touch down + up (simulate a tap at center of 1080x1920 screen)
      print('Sending touch DOWN...');
      server!.sendControlMessage(
        const ScrcpyInjectTouchMessage(
          action: ScrcpyAction.down,
          pointerId: 1,
          x: 540,
          y: 960,
          width: 1080,
          height: 1920,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      print('Sending touch UP...');
      server!.sendControlMessage(
        const ScrcpyInjectTouchMessage(
          action: ScrcpyAction.up,
          pointerId: 1,
          x: 540,
          y: 960,
          width: 1080,
          height: 1920,
        ),
      );

      // Send a key event (home button — should be visible on device)
      print('Sending HOME key...');
      server!.sendControlMessage(
        const ScrcpyInjectKeyMessage(
          action: ScrcpyAction.down,
          keycode: ScrcpyKeycode.home,
        ),
      );
      server!.sendControlMessage(
        const ScrcpyInjectKeyMessage(
          action: ScrcpyAction.up,
          keycode: ScrcpyKeycode.home,
        ),
      );

      print('All control messages sent without error.');
    },
        timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
