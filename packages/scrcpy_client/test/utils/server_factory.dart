import 'dart:async';
import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

(ScrcpyServer, List<List<int>>) createTestServer(
  ScrcpyAdb adb, {
  String deviceId = 'test-device',
  Uint8List? jarBytes,
}) {
  final captured = <List<int>>[];
  final controller = StreamController<List<int>>(sync: true);
  addTearDown(controller.close);
  controller.stream.listen(captured.add);
  final server = ScrcpyServer(
    adb: adb,
    deviceId: deviceId,
    serverJarBytes: jarBytes ?? Uint8List(0),
    options: const ScrcpyServerOptions(),
    controlSink: controller.sink,
  );
  return (server, captured);
}
