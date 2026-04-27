import 'dart:typed_data';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/src/control_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(initAppLogger);

  group('ScrcpyInjectTouchMessage', () {
    test('binary layout matches scrcpy v3 ControlMessageReader (32 bytes)', () {
      const msg = ScrcpyInjectTouchMessage(
        action: ScrcpyAction.down,
        pointerId: 0xDEADBEEFCAFEBABE,
        x: 540,
        y: 960,
        width: 1080,
        height: 1920,
      );

      final bytes = msg.toBinary();

      // 32 bytes per scrcpy v3 layout:
      //   type(1) action(1) pointerId(8) x(4) y(4) w(2) h(2)
      //   pressure(2) actionButton(4) buttons(4)
      expect(bytes.length, 32);
      final bd = ByteData.sublistView(bytes);

      // Byte 0: type = 2 (inject touch)
      expect(bd.getUint8(0), 2);

      // Byte 1: action = 0 (down)
      expect(bd.getUint8(1), ScrcpyAction.down);

      // Bytes 2-9: 8-byte pointerId, big-endian
      expect(bd.getUint64(2), 0xDEADBEEFCAFEBABE);

      // Bytes 10-13: x
      expect(bd.getUint32(10), 540);

      // Bytes 14-17: y
      expect(bd.getUint32(14), 960);

      // Bytes 18-19: width (uint16)
      expect(bd.getUint16(18), 1080);

      // Bytes 20-21: height (uint16)
      expect(bd.getUint16(20), 1920);

      // Bytes 22-23: pressure (0-65535). 1.0 → 65535
      expect(bd.getUint16(22), 65535);

      // Bytes 24-27: actionButton
      expect(bd.getUint32(24), 0);

      // Bytes 28-31: buttons
      expect(bd.getUint32(28), 0);
    });

    test('pressure maps [0.0, 1.0] to uint16 [0, 65535]', () {
      expectPressure(0, 0);
      expectPressure(0.5, 32767);
      expectPressure(1, 65535);
      // Clamped
      expectPressure(1.5, 65535);
      expectPressure(-0.5, 0);
    });

    test('action constants: down=0, up=1, move=2, cancel=3', () {
      final actions = [
        (ScrcpyAction.down, 0),
        (ScrcpyAction.up, 1),
        (ScrcpyAction.move, 2),
        (ScrcpyAction.cancel, 3),
      ];
      for (final (action, expected) in actions) {
        final bytes = ScrcpyInjectTouchMessage(
          action: action,
          pointerId: 0,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ).toBinary();
        expect(bytes[1], expected,
            reason: 'action $action should encode as $expected');
      }
    });

    test('actionButton and buttons are encoded at correct offsets', () {
      const msg = ScrcpyInjectTouchMessage(
        action: ScrcpyAction.down,
        pointerId: 0,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        actionButton: 0x01, // BUTTON_PRIMARY
        buttons: 0x01000000,
      );
      final bd = ByteData.sublistView(msg.toBinary());
      expect(bd.getUint32(24), 0x01);
      expect(bd.getUint32(28), 0x01000000);
    });
  });

  group('ScrcpyInjectKeyMessage', () {
    test('binary layout is 14 bytes with correct field offsets', () {
      const msg = ScrcpyInjectKeyMessage(
        action: ScrcpyAction.down,
        keycode: ScrcpyKeycode.home,
      );

      final bytes = msg.toBinary();
      expect(bytes.length, 14);
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 0); // type = 0
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint32(2), ScrcpyKeycode.home); // 3
      expect(bd.getUint32(6), 0); // repeat
      expect(bd.getUint32(10), 0); // metastate
    });

    test('keycodes: home=3, back=4, appSwitch=187', () {
      for (final (keycode, expected) in [
        (ScrcpyKeycode.home, 3),
        (ScrcpyKeycode.back, 4),
        (ScrcpyKeycode.appSwitch, 187),
      ]) {
        final msg =
            ScrcpyInjectKeyMessage(action: ScrcpyAction.down, keycode: keycode);
        final bd = ByteData.sublistView(msg.toBinary());
        expect(bd.getUint32(2), expected, reason: 'keycode $keycode mismatch');
      }
    });
  });

  group('ScrcpyInjectTextMessage', () {
    test('UTF-8 text is encoded with 4-byte length prefix', () {
      const text = 'hello';
      const msg = ScrcpyInjectTextMessage(text);

      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 1); // type = 1
      expect(bd.getUint32(1), text.length); // UTF-8 byte count
      final payload = bytes.sublist(5);
      expect(payload, text.codeUnits);
    });

    test('handles empty string', () {
      final bytes = const ScrcpyInjectTextMessage('').toBinary();
      // 5 bytes: type(1) + length(4), no payload
      expect(bytes.length, 5);
      expect(ByteData.sublistView(bytes).getUint32(1), 0);
    });

    test('handles multi-byte UTF-8 characters', () {
      const text = '你好';
      final bytes = const ScrcpyInjectTextMessage(text).toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint32(1), 6); // 2 chars × 3 bytes each in UTF-8
      expect(bytes.length, 5 + 6);
    });
  });

  group('ScrcpyInjectScrollMessage', () {
    test('binary layout is 25 bytes with signed scroll values', () {
      const msg = ScrcpyInjectScrollMessage(
        x: 100,
        y: 200,
        width: 1080,
        height: 1920,
        hScroll: -10,
        vScroll: 50,
      );

      final bytes = msg.toBinary();
      expect(bytes.length, 25);
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 3); // type = 3
      expect(bd.getUint32(1), 100); // x
      expect(bd.getUint32(5), 200); // y
      expect(bd.getUint16(9), 1080); // width
      expect(bd.getUint16(11), 1920); // height
      expect(bd.getInt32(13), -10); // hScroll (signed)
      expect(bd.getInt32(17), 50); // vScroll (signed)
      expect(bd.getUint32(21), 0); // buttons
    });
  });

  group('ScrcpyBackOrScreenOnMessage', () {
    test('binary layout is 2 bytes', () {
      final bytes =
          const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down).toBinary();

      expect(bytes.length, 2);
      expect(bytes[0], 4); // type = 4
      expect(bytes[1], ScrcpyAction.down);
    });
  });
}

/// Helper: assert pressure encodes to expected uint16 value.
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
  expect(bd.getUint16(22), expected,
      reason: 'pressure $input should encode as $expected');
}
