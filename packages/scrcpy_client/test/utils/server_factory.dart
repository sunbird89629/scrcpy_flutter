import 'dart:async';
import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'mock_device_provisioner.dart';
import 'real_adb.dart';

(ScrcpyServer, List<List<int>>) createTestServer({
  String deviceId = 'test-device',
  Uint8List? jarBytes,
}) {
  final captured = <List<int>>[];
  final controller = StreamController<List<int>>(sync: true);
  addTearDown(controller.close);
  controller.stream.listen(captured.add);
  final provisioner = MockDeviceProvisioner(deviceId: deviceId);
  final server = ScrcpyServer(
    provisioner: provisioner,
    controlSink: controller.sink,
  );
  return (server, captured);
}

ScrcpyServer createRealServer({
  String deviceId = 'test-device',
  Uint8List? jarBytes,
}) {
  final provisioner = AdbScrcpyDeviceProvisioner(
    adb: RealAdb(),
    deviceId: deviceId,
    serverJarBytes: jarBytes ?? Uint8List(0),
    options: const ScrcpyServerOptions(),
  );
  final server = ScrcpyServer(provisioner: provisioner);
  return server;
}
