import 'dart:async';
import 'dart:typed_data';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(initAppLogger);

  /// Helper: creates a [ScrcpyServer] with an injected capture sink.
  (ScrcpyServer, List<List<int>>) createServer() {
    final captured = <List<int>>[];
    final controller = StreamController<List<int>>(sync: true);
    controller.stream.listen(captured.add);
    final server = ScrcpyServer(
      adbClient: const AdbClient(),
      deviceId: 'test-device',
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
      expect(bd.getUint8(0), 0); // type
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint32(2), ScrcpyKeycode.home); // keycode
      expect(bd.getUint32(6), 0); // repeat
      expect(bd.getUint32(10), 0); // metastate
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
      expect(bd.getInt16(13), -10);
      expect(bd.getInt16(15), 50);
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
