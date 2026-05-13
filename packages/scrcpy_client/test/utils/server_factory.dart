import 'dart:async';
import 'dart:typed_data';

import 'package:scrcpy_client/src/scrcpy_server.dart';
import 'package:test/test.dart';

import 'no_op_adb.dart';

(ScrcpyServer, List<List<int>>) createTestServer() {
  final captured = <List<int>>[];
  final controller = StreamController<List<int>>(sync: true);
  addTearDown(controller.close);
  controller.stream.listen(captured.add);
  final server = ScrcpyServer(
    adb: const NoOpAdb(),
    deviceId: 'test-device',
    serverJarBytes: Uint8List(0),
    controlSink: controller.sink,
  );
  return (server, captured);
}
