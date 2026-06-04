import 'dart:typed_data';

import 'package:scrcpy_client/src/messages/control_message.dart';
import 'package:test/test.dart';

import 'utils/server_factory.dart';

void main() {
  group('sendControlMessage via injected sink', () {
    test('touch message (type 2) writes 32 bytes', () {
      final (server, captured) = createTestServer();
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
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 32);
      expect(bd.getUint8(0), 2);
      expect(bd.getUint8(1), ScrcpyAction.down);
    });

    test('keycode message (type 0) writes 14 bytes', () {
      final (server, captured) = createTestServer();
      server.sendControlMessage(
        const ScrcpyInjectKeyMessage(
          action: ScrcpyAction.down,
          keycode: ScrcpyKeycode.home,
        ),
      );
      expect(captured.length, 1);
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 14);
      expect(bd.getUint8(0), 0);
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint32(2), ScrcpyKeycode.home);
    });

    test('scroll message (type 3) writes 21 bytes', () {
      final (server, captured) = createTestServer();
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
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 21);
      expect(bd.getUint8(0), 3);
      expect(bd.getInt16(13), -20479);
      expect(bd.getInt16(15), 32767);
    });

    test('set-clipboard with paste=false sends 0 at paste offset', () {
      final (server, captured) = createTestServer();
      server.sendControlMessage(
        const ScrcpySetClipboardMessage(text: 'abc', paste: false),
      );
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(bd.getUint8(9), 0);
    });

    test('back-or-screen-on message (type 4) writes 2 bytes', () {
      final (server, captured) = createTestServer();
      server.sendControlMessage(
        const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down),
      );
      expect(captured.length, 1);
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 2);
      expect(bd.getUint8(0), 4);
      expect(bd.getUint8(1), ScrcpyAction.down);
    });
  });
}
