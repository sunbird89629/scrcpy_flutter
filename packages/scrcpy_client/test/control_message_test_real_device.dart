import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'utils/real_adb.dart';
import 'utils/server_factory.dart';

void main() {
  late RealAdb adb;
  late String realDeviceId;
  late Uint8List realJarBytes;

  setUpAll(() async {
    adb = RealAdb();
    final devices = await adb.getDevices();
    if (devices.isEmpty) {
      throw StateError('No ADB devices connected — plug in a device first');
    }
    realDeviceId = devices.first;
    realJarBytes = await File(
      'assets/scrcpy-server-v${ScrcpyServer.serverVersion}',
    ).readAsBytes();
  });

  test('expand notification panel in real device', () async {
    final scrcpyServer = createRealServer(
      deviceId: realDeviceId,
      jarBytes: realJarBytes,
    );
    await scrcpyServer.start();
    // scrcpyServer.sendControlMessage(ScrcpyExpandNotificationPanelMessage());
    scrcpyServer.sendControlMessage(ScrcpyExpandSettingsPanelMessage());
  });
}

void expectPressure(double input, int expected) {
  final msg = ScrcpyInjectTouchMessage(
    action: ScrcpyAction.down,
    pointerId: 0,
    x: 0,
    y: 0,
    width: 1,
    height: 1,
    pressure: input,
  );
  final bd = ByteData.sublistView(msg.toBinary());
  expect(
    bd.getUint16(22),
    expected,
    reason: 'pressure $input should encode as $expected',
  );
}
