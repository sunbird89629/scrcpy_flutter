import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_adb.dart';
import 'package:scrcpy_client/src/scrcpy_server.dart';
import 'package:test/test.dart';

class _NoOpAdb implements ScrcpyAdb {
  const _NoOpAdb();

  @override
  String get adbPath => 'adb';

  @override
  Future<List<String>> getDevices() async => [];

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async => ProcessResult(0, 0, '', '');

  @override
  Future<void> forward(String local, String remote,
      {String? deviceId, bool noRebind = false}) async {}

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {}

  @override
  Future<void> push(String localPath, String remotePath,
      {String? deviceId}) async {}

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async => Uint8List(0);
}

void main() {
  (ScrcpyServer, List<List<int>>) createServer() {
    final captured = <List<int>>[];
    final controller = StreamController<List<int>>(sync: true);
    controller.stream.listen(captured.add);
    final server = ScrcpyServer(
      adb: const _NoOpAdb(),
      deviceId: 'test-device',
      serverJarBytes: Uint8List(0),
      controlSink: controller.sink,
    );
    return (server, captured);
  }

  group('sendControlMessage via injected sink', () {
    test('touch message (type 2) writes 32 bytes', () {
      final (server, captured) = createServer();
      server.sendControlMessage(const ScrcpyInjectTouchMessage(
        action: ScrcpyAction.down, pointerId: 1,
        x: 100, y: 200, width: 1080, height: 1920,
      ));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 32);
      expect(bd.getUint8(0), 2);
      expect(bd.getUint8(1), ScrcpyAction.down);
    });

    test('keycode message (type 0) writes 14 bytes', () {
      final (server, captured) = createServer();
      server.sendControlMessage(const ScrcpyInjectKeyMessage(
        action: ScrcpyAction.down, keycode: ScrcpyKeycode.home,
      ));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 14);
      expect(bd.getUint8(0), 0);
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint32(2), ScrcpyKeycode.home);
    });

    test('scroll message (type 3) writes 21 bytes', () {
      final (server, captured) = createServer();
      server.sendControlMessage(const ScrcpyInjectScrollMessage(
        x: 100, y: 200, width: 1080, height: 1920,
        hScroll: -10, vScroll: 50,
      ));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 21);
      expect(bd.getUint8(0), 3);
      expect(bd.getInt16(13), -20479);
      expect(bd.getInt16(15), 32767);
    });

    test('set-clipboard with paste=false sends 0 at paste offset', () {
      final (server, captured) = createServer();
      server.sendControlMessage(
          const ScrcpySetClipboardMessage(text: 'abc', paste: false));
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(bd.getUint8(9), 0);
    });

    test('back-or-screen-on message (type 4) writes 2 bytes', () {
      final (server, captured) = createServer();
      server.sendControlMessage(
          const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 2);
      expect(bd.getUint8(0), 4);
      expect(bd.getUint8(1), ScrcpyAction.down);
    });
  });
}
