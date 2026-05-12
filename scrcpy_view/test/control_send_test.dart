import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_adb.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';

/// Minimal no-op ADB implementation for tests that don't need real ADB.
class _NoOpAdb implements ScrcpyAdb {
  const _NoOpAdb();

  @override  String get adbPath => 'adb';

  @override
  Future<List<String>> getDevices() async => [];

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return ProcessResult(0, 0, '', '');
  }

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {}

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {}

  @override
  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) async {}

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
      webPlayerBytes: Uint8List(0),
      controlSink: controller.sink,
    );
    return (server, captured);
  }

  group('sendControlMessage via injected sink', () {
    test('touch message (type 2) writes 32 bytes', () {
      final (server, captured) = createServer();

      server.sendControlMessage(
        const ScrcpyInjectTouchMessage(
          action: ScrcpyAction.down,
          pointerId: 1,
          x: 100,
          y: 200,
          width: 1080,
          height: 1920,
        ),
      );

      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 32);
      expect(bd.getUint8(0), 2);
      expect(bd.getUint8(1), ScrcpyAction.down);
    });

    test('keycode message (type 0) writes 14 bytes', () {
      final (server, captured) = createServer();

      server.sendControlMessage(
        const ScrcpyInjectKeyMessage(
          action: ScrcpyAction.down,
          keycode: ScrcpyKeycode.home,
        ),
      );

      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 14);
      expect(bd.getUint8(0), 0);
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint32(2), ScrcpyKeycode.home);
      expect(bd.getUint32(6), 0);
      expect(bd.getUint32(10), 0);
    });

    test('text message (type 1) writes 5 + UTF-8 length bytes', () {
      final (server, captured) = createServer();

      const text = 'hello';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));

      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 5 + text.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), text.length);
      final payload = captured.single.sublist(5);
      expect(payload, text.codeUnits);
    });

    test('scroll message (type 3) writes 21 bytes', () {
      final (server, captured) = createServer();

      server.sendControlMessage(
        const ScrcpyInjectScrollMessage(
          x: 100,
          y: 200,
          width: 1080,
          height: 1920,
          hScroll: -10,
          vScroll: 50,
        ),
      );

      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 21);
      expect(bd.getUint8(0), 3);
      expect(bd.getUint32(1), 100);
      expect(bd.getUint32(5), 200);
      expect(bd.getUint16(9), 1080);
      expect(bd.getUint16(11), 1920);
      // hScroll=-10 → -10/16=-0.625 → i16fp=-20479
      expect(bd.getInt16(13), -20479);
      // vScroll=50 → 50/16=3.125, clamped=1.0 → i16fp=32767
      expect(bd.getInt16(15), 32767);
    });

    test('set-clipboard message (type 9) writes 14 + UTF-8 bytes', () {
      final (server, captured) = createServer();

      const text = '你好世界'; // 4 chars × 3 UTF-8 bytes = 12 bytes
      server.sendControlMessage(
        const ScrcpySetClipboardMessage(text: text, sequence: 42),
      );

      expect(captured.length, 1);
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 14 + 12);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint64(1), 42);
      expect(bd.getUint8(9), 1); // paste=true
      expect(bd.getUint32(10), 12);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('set-clipboard with paste=false sends 0 at paste offset', () {
      final (server, captured) = createServer();

      server.sendControlMessage(
        const ScrcpySetClipboardMessage(text: 'abc', paste: false),
      );

      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(bd.getUint8(9), 0);
    });

    test('back-or-screen-on message (type 4) writes 2 bytes', () {
      final (server, captured) = createServer();

      server.sendControlMessage(
        const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down),
      );

      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 2);
      expect(bd.getUint8(0), 4);
      expect(bd.getUint8(1), ScrcpyAction.down);
    });
  });
}
