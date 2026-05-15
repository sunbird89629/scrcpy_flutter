import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

void main() {
  group('ScrcpyDeviceMessageParser', () {
    // type=0, sequence=1 (uint64 BE), length=2 (uint32 BE), text="ok" (0x6F,0x6B)
    final type0Bytes = Uint8List.fromList([
      0x00, // type
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // sequence=1
      0x00, 0x00, 0x00, 0x02, // length=2
      0x6F, 0x6B, // "ok"
    ]);

    // type=1, sequence=42 (0x2A)
    final type1Bytes = Uint8List.fromList([
      0x01, // type
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2A, // sequence=42
    ]);

    // type=2, id=7, size=2, data=[0xAB, 0xCD]
    final type2Bytes = Uint8List.fromList([
      0x02, // type
      0x00, 0x07, // id=7
      0x00, 0x02, // size=2
      0xAB, 0xCD, // data
    ]);

    test('type 0: emits ScrcpyClipboardDeviceMessage with sequence and text',
        () async {
      final parser = ScrcpyDeviceMessageParser();
      addTearDown(() => parser.close());

      final msgFuture = parser.messages.first;
      parser.feed(type0Bytes);
      final msg = await msgFuture as ScrcpyClipboardDeviceMessage;

      expect(msg.sequence, 1);
      expect(msg.text, 'ok');
    });

    test('type 1: emits ScrcpyAckClipboardDeviceMessage with sequence',
        () async {
      final parser = ScrcpyDeviceMessageParser();
      addTearDown(() => parser.close());

      final msgFuture = parser.messages.first;
      parser.feed(type1Bytes);
      final msg = await msgFuture as ScrcpyAckClipboardDeviceMessage;

      expect(msg.sequence, 42);
    });

    test('type 2: emits ScrcpyUhidOutputDeviceMessage with id and data',
        () async {
      final parser = ScrcpyDeviceMessageParser();
      addTearDown(() => parser.close());

      final msgFuture = parser.messages.first;
      parser.feed(type2Bytes);
      final msg = await msgFuture as ScrcpyUhidOutputDeviceMessage;

      expect(msg.id, 7);
      expect(msg.data, [0xAB, 0xCD]);
    });

    test('type 0 with non-ASCII text: decodes UTF-8 byte count correctly',
        () async {
      // "你好" = [0xE4,0xBD,0xA0, 0xE5,0xA5,0xBD] — 6 UTF-8 bytes
      final bytes = Uint8List.fromList([
        0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // sequence=1
        0x00, 0x00, 0x00, 0x06, // length=6 (bytes, not chars)
        0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD, // "你好"
      ]);

      final parser = ScrcpyDeviceMessageParser();
      addTearDown(() => parser.close());

      final msgFuture = parser.messages.first;
      parser.feed(bytes);
      final msg = await msgFuture as ScrcpyClipboardDeviceMessage;

      expect(msg.text, '你好');
    });

    test('fragmented feed: two feeds produce one event', () async {
      final parser = ScrcpyDeviceMessageParser();
      addTearDown(() => parser.close());

      // Split the 15-byte type-0 message at index 7
      parser.feed(Uint8List.sublistView(type0Bytes, 0, 7));

      // Not enough bytes yet — drain microtasks and verify no event
      await Future(() {});
      // Buffer has 7 bytes, need 13 for type 0 — no event emitted

      final msgFuture = parser.messages.first;
      parser.feed(Uint8List.sublistView(type0Bytes, 7));
      final msg = await msgFuture as ScrcpyClipboardDeviceMessage;

      expect(msg.text, 'ok');
    });

    test('concatenated messages: two type-1 messages in one feed', () async {
      final parser = ScrcpyDeviceMessageParser();
      addTearDown(() => parser.close());

      final msgsFuture = parser.messages.take(2).toList();
      parser.feed(Uint8List.fromList([
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02,
      ]));

      final msgs = await msgsFuture;
      expect(msgs, hasLength(2));
      expect((msgs[0] as ScrcpyAckClipboardDeviceMessage).sequence, 1);
      expect((msgs[1] as ScrcpyAckClipboardDeviceMessage).sequence, 2);
    });

    test('mixed messages: type-0 then type-1 in one feed', () async {
      final parser = ScrcpyDeviceMessageParser();
      addTearDown(() => parser.close());

      final msgsFuture = parser.messages.take(2).toList();
      parser.feed(Uint8List.fromList([...type0Bytes, ...type1Bytes]));

      final msgs = await msgsFuture;
      expect(msgs[0], isA<ScrcpyClipboardDeviceMessage>());
      expect(msgs[1], isA<ScrcpyAckClipboardDeviceMessage>());
    });

    test('unknown type: no crash, no further events emitted', () async {
      final parser = ScrcpyDeviceMessageParser();
      addTearDown(() => parser.close());

      final events = <ScrcpyDeviceMessage>[];
      parser.messages.listen(events.add);

      parser.feed(Uint8List.fromList([0xFF, 0x01, 0x02]));

      // Allow microtasks to drain
      await Future(() {});
      expect(events, isEmpty);
    });
  });
}
