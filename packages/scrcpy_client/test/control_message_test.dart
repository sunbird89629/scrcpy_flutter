import 'dart:convert';
import 'dart:typed_data';

import 'package:scrcpy_client/src/messages/control_message.dart';
import 'package:test/test.dart';

void main() {
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

      expect(bytes.length, 32);
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 2);
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint64(2), 0xDEADBEEFCAFEBABE);
      expect(bd.getUint32(10), 540);
      expect(bd.getUint32(14), 960);
      expect(bd.getUint16(18), 1080);
      expect(bd.getUint16(20), 1920);
      expect(bd.getUint16(22), 65535);
      expect(bd.getUint32(24), 0);
      expect(bd.getUint32(28), 0);
    });

    test('pressure maps [0.0, 1.0] to uint16 [0, 65535]', () {
      expectPressure(0, 0);
      expectPressure(0.5, 32767);
      expectPressure(1, 65535);
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
        actionButton: 0x01,
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

      expect(bd.getUint8(0), 0);
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint32(2), ScrcpyKeycode.home);
      expect(bd.getUint32(6), 0);
      expect(bd.getUint32(10), 0);
    });

    test('keycodes: home=3, back=4, appSwitch=187', () {
      for (final (keycode, expected) in [
        (ScrcpyKeycode.home, 3),
        (ScrcpyKeycode.back, 4),
        (ScrcpyKeycode.appSwitch, 187),
      ]) {
        final msg = ScrcpyInjectKeyMessage(
          action: ScrcpyAction.down,
          keycode: keycode,
        );
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

      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), text.length);
      final payload = bytes.sublist(5);
      expect(payload, text.codeUnits);
    });

    test('handles empty string', () {
      final bytes = const ScrcpyInjectTextMessage('').toBinary();
      expect(bytes.length, 5);
      expect(ByteData.sublistView(bytes).getUint32(1), 0);
    });

    test('handles multi-byte UTF-8 characters', () {
      const text = '你好';
      final bytes = const ScrcpyInjectTextMessage(text).toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint32(1), 6);
      expect(bytes.length, 5 + 6);
    });
  });

  group('ScrcpyInjectScrollMessage', () {
    test('binary layout is 21 bytes with i16fp-encoded scroll values', () {
      const msg = ScrcpyInjectScrollMessage(
        x: 100, y: 200, width: 1080, height: 1920,
        hScroll: -10, vScroll: 50,
      );

      final bytes = msg.toBinary();
      expect(bytes.length, 21);
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 3);
      expect(bd.getUint32(1), 100);
      expect(bd.getUint32(5), 200);
      expect(bd.getUint16(9), 1080);
      expect(bd.getUint16(11), 1920);
      expect(bd.getInt16(13), -20479);
      expect(bd.getInt16(15), 32767);
      expect(bd.getUint32(17), 0);
    });

    test('values clamped to max scroll magnitude outside [-16, 16]', () {
      const msg = ScrcpyInjectScrollMessage(
        x: 0, y: 0, width: 1080, height: 1920,
        hScroll: -100, vScroll: 100,
      );
      final bd = ByteData.sublistView(msg.toBinary());
      expect(bd.getInt16(13), -32767);
      expect(bd.getInt16(15), 32767);
    });
  });

  group('ScrcpySetClipboardMessage', () {
    test('binary layout: type=9, sequence(8), paste(1), text_len(4), utf8', () {
      const msg = ScrcpySetClipboardMessage(text: 'hello', sequence: 1);
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bytes.length, 14 + 5);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint64(1), 1);
      expect(bd.getUint8(9), 1);
      expect(bd.getUint32(10), 5);
      expect(bytes.sublist(14), 'hello'.codeUnits);
    });

    test('Chinese text: text_len reflects UTF-8 byte count, not char count', () {
      const msg = ScrcpySetClipboardMessage(text: '你好');
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bytes.length, 14 + 6);
      expect(bd.getUint32(10), 6);
    });

    test('paste=false encodes paste byte as 0', () {
      const msg = ScrcpySetClipboardMessage(text: 'x', paste: false);
      final bd = ByteData.sublistView(msg.toBinary());
      expect(bd.getUint8(9), 0);
    });

    test('empty text produces 14-byte message with text_len=0', () {
      const msg = ScrcpySetClipboardMessage(text: '');
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 14);
      expect(bd.getUint32(10), 0);
    });

    test('sequence is encoded as uint64 at offset 1', () {
      const msg = ScrcpySetClipboardMessage(
        text: '', sequence: 0xDEADBEEFCAFEBABE,
      );
      final bd = ByteData.sublistView(msg.toBinary());
      expect(bd.getUint64(1), 0xDEADBEEFCAFEBABE);
    });
  });

  group('ScrcpyBackOrScreenOnMessage', () {
    test('binary layout is 2 bytes', () {
      final bytes =
          const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down).toBinary();
      expect(bytes.length, 2);
      expect(bytes[0], 4);
      expect(bytes[1], ScrcpyAction.down);
    });
  });

  group('ScrcpyExpandNotificationPanelMessage', () {
    test('binary layout is 1 byte containing only type 5', () {
      final bytes =
          const ScrcpyExpandNotificationPanelMessage().toBinary();
      expect(bytes.length, 1);
      expect(bytes[0], 5);
    });
  });

  group('ScrcpyCollapsePanelsMessage', () {
    test('binary layout is 1 byte containing only type 7', () {
      final bytes = const ScrcpyCollapsePanelsMessage().toBinary();
      expect(bytes.length, 1);
      expect(bytes[0], 7);
    });
  });

  group('ScrcpyStartAppMessage', () {
    test('binary layout: type=16, name_len(1), utf8 name', () {
      const msg = ScrcpyStartAppMessage('firefox');
      final bytes = msg.toBinary();

      expect(bytes.length, 9);
      expect(bytes[0], 16);
      expect(bytes[1], 7);
      expect(bytes.sublist(2), 'firefox'.codeUnits);
    });

    test('handles empty app name', () {
      final bytes = const ScrcpyStartAppMessage('').toBinary();
      expect(bytes.length, 2);
      expect(bytes[0], 16);
      expect(bytes[1], 0);
    });
  });

  group('ScrcpyExpandSettingsPanelMessage', () {
    test('binary layout is 1 byte containing only type 6', () {
      final bytes = const ScrcpyExpandSettingsPanelMessage().toBinary();
      expect(bytes.length, 1);
      expect(bytes[0], 6);
    });
  });

  group('ScrcpyGetClipboardMessage', () {
    test('default: type=8, copyKey=none(0)', () {
      final bytes = const ScrcpyGetClipboardMessage().toBinary();
      expect(bytes.length, 2);
      expect(bytes[0], 8);
      expect(bytes[1], ScrcpyClipboardCopyKey.none);
    });

    test('copyKey=copy encodes as 1', () {
      final bytes =
          const ScrcpyGetClipboardMessage(
            copyKey: ScrcpyClipboardCopyKey.copy,
          ).toBinary();
      expect(bytes[1], 1);
    });
  });

  group('ScrcpySetDisplayPowerMessage', () {
    test('on=true encodes as type=10, byte=1', () {
      final bytes =
          const ScrcpySetDisplayPowerMessage(on: true).toBinary();
      expect(bytes.length, 2);
      expect(bytes[0], 10);
      expect(bytes[1], 1);
    });

    test('on=false encodes as type=10, byte=0', () {
      final bytes =
          const ScrcpySetDisplayPowerMessage(on: false).toBinary();
      expect(bytes[1], 0);
    });
  });

  group('ScrcpyRotateDeviceMessage', () {
    test('binary layout is 1 byte containing only type 11', () {
      final bytes = const ScrcpyRotateDeviceMessage().toBinary();
      expect(bytes.length, 1);
      expect(bytes[0], 11);
    });
  });

  group('ScrcpyUhidCreateMessage', () {
    test('full binary layout matches C test serialization', () {
      final msg = ScrcpyUhidCreateMessage(
        id: 42,
        vendorId: 0x1234,
        productId: 0x5678,
        name: 'test',
        reportDescriptor: Uint8List.fromList([1, 2, 3]),
      );
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);

      // type(1) + id(2) + vendor_id(2) + product_id(2) + name_size(1)
      //   = 8 byte header
      expect(bytes.length, 8 + 4 + 2 + 3); // header + name + desc_size + desc
      expect(bd.getUint8(0), 12);
      expect(bd.getUint16(1), 42);
      expect(bd.getUint16(3), 0x1234);
      expect(bd.getUint16(5), 0x5678);
      expect(bd.getUint8(7), 4); // name_size = utf8.encode('test').length
      // name bytes
      expect(utf8.decode(bytes.sublist(8, 12)), 'test');
      // report_desc_size at offset 12
      expect(bd.getUint16(12), 3);
      // report_desc bytes
      expect(bytes.sublist(14), [1, 2, 3]);
    });

    test('defaults: vendorId=0 productId=0 name="" reportDescriptor=[]', () {
      final bytes =
          ScrcpyUhidCreateMessage(id: 1).toBinary();
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 10); // header(8) + desc_size(2) + empty desc
      expect(bd.getUint16(3), 0);
      expect(bd.getUint16(5), 0);
      expect(bd.getUint8(7), 0);
      expect(bd.getUint16(8), 0);
    });
  });

  group('ScrcpyUhidInputMessage', () {
    test('binary layout: type=13, id(2), size(2), data(var)', () {
      final msg = ScrcpyUhidInputMessage(
        id: 0x42,
        data: Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 10);
      expect(bd.getUint8(0), 13);
      expect(bd.getUint16(1), 0x42);
      expect(bd.getUint16(3), 5);
      expect(bytes.sublist(5), [1, 2, 3, 4, 5]);
    });
  });

  group('ScrcpyUhidDestroyMessage', () {
    test('binary layout: type=14, id(2)', () {
      const msg = ScrcpyUhidDestroyMessage(id: 0x42);
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 3);
      expect(bd.getUint8(0), 14);
      expect(bd.getUint16(1), 0x42);
    });
  });

  group('ScrcpyOpenHardKeyboardSettingsMessage', () {
    test('binary layout is 1 byte containing only type 15', () {
      final bytes =
          const ScrcpyOpenHardKeyboardSettingsMessage().toBinary();
      expect(bytes.length, 1);
      expect(bytes[0], 15);
    });
  });

  group('ScrcpyResetVideoMessage', () {
    test('binary layout is 1 byte containing only type 17', () {
      final bytes = const ScrcpyResetVideoMessage().toBinary();
      expect(bytes.length, 1);
      expect(bytes[0], 17);
    });
  });

  group('ScrcpyCameraSetTorchMessage', () {
    test('on=true encodes as type=18, byte=1', () {
      final bytes =
          const ScrcpyCameraSetTorchMessage(on: true).toBinary();
      expect(bytes.length, 2);
      expect(bytes[0], 18);
      expect(bytes[1], 1);
    });
  });

  group('ScrcpyCameraZoomInMessage', () {
    test('binary layout is 1 byte containing only type 19', () {
      final bytes = const ScrcpyCameraZoomInMessage().toBinary();
      expect(bytes.length, 1);
      expect(bytes[0], 19);
    });
  });

  group('ScrcpyCameraZoomOutMessage', () {
    test('binary layout is 1 byte containing only type 20', () {
      final bytes = const ScrcpyCameraZoomOutMessage().toBinary();
      expect(bytes.length, 1);
      expect(bytes[0], 20);
    });
  });

  group('ScrcpyResizeDisplayMessage', () {
    test('binary layout: type=21, width(2), height(2)', () {
      const msg = ScrcpyResizeDisplayMessage(width: 1920, height: 1080);
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 5);
      expect(bd.getUint8(0), 21);
      expect(bd.getUint16(1), 1920);
      expect(bd.getUint16(3), 1080);
    });
  });
}

void expectPressure(double input, int expected) {
  final msg = ScrcpyInjectTouchMessage(
    action: ScrcpyAction.down,
    pointerId: 0, x: 0, y: 0, width: 1, height: 1,
    pressure: input,
  );
  final bd = ByteData.sublistView(msg.toBinary());
  expect(bd.getUint16(22), expected,
      reason: 'pressure $input should encode as $expected');
}
