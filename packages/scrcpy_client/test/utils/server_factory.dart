import 'dart:async';
import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'no_op_adb.dart';
import 'real_adb.dart';

(ScrcpyServer, List<List<int>>) createTestServer({
  String deviceId = 'test-device',
  Uint8List? jarBytes,
}) {
  final captured = <List<int>>[];
  final controller = StreamController<List<int>>(sync: true);
  addTearDown(controller.close);
  controller.stream.listen(captured.add);
  final server = ScrcpyServer(
    adb: NoOpAdb(),
    deviceId: deviceId,
    serverJarBytes: jarBytes ?? Uint8List(0),
    options: const ScrcpyServerOptions(),
    controlSink: controller.sink,
  );
  return (server, captured);
}

(ScrcpyServer, List<List<int>>) ceateRealServer({
  String deviceId = 'test-device',
  Uint8List? jarBytes,
}) {
  final captured = <List<int>>[];
  // final controller = StreamController<List<int>>(sync: true);
  // addTearDown(controller.close);
  // controller.stream.listen(captured.add);
  final server = ScrcpyServer(
    adb: RealAdb(),
    deviceId: deviceId,
    serverJarBytes: jarBytes ?? Uint8List(0),
    options: const ScrcpyServerOptions(),
    // controlSink: controller.sink,
  );
  return (server, captured);
}
