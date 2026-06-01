import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'utils/server_factory.dart';

void main() {
  group('ScrcpyServer.deviceMessages', () {
    test('emits ScrcpyClipboardDeviceMessage when fed type-0 bytes', () async {
      final (server, _) = createTestServer();

      final events = <ScrcpyDeviceMessage>[];
      final sub = server.deviceMessages.listen(events.add);
      addTearDown(sub.cancel);

      // type=0, sequence=1, length=2, text="ok"
      server.feedDeviceBytes(
        Uint8List.fromList([
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x02,
          0x6F,
          0x6B,
        ]),
      );

      // broadcast stream delivers via microtask
      await Future(() {});

      expect(events, hasLength(1));
      final msg = events.first as ScrcpyClipboardDeviceMessage;
      expect(msg.sequence, 1);
      expect(msg.text, 'ok');
    });

    test('stop() closes the deviceMessages stream', () async {
      final (server, _) = createTestServer();

      var done = false;
      server.deviceMessages.listen(null, onDone: () => done = true);

      await server.stop();
      await Future(() {});

      expect(done, isTrue);
    });
  });
}
