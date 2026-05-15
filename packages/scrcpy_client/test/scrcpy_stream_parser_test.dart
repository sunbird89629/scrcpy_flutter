import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

void main() {
  group('ScrcpyStreamParser', () {
    test('parses metadata and packets correctly', () async {
      final parser = ScrcpyStreamParser();
      final metadataFuture = parser.metadata.first;
      final packetsFuture = parser.packets.take(2).toList();

      final header = Uint8List(64 + 12);
      const name = 'TestDevice';
      for (var i = 0; i < name.length; i++) {
        header[i] = name.codeUnitAt(i);
      }
      ByteData.sublistView(header, 64)
        ..setUint32(0, 0x68323634) // h264
        ..setUint32(4, 1080)
        ..setUint32(8, 1920);

      final configPacket = Uint8List(12 + 5);
      final configBd = ByteData.sublistView(configPacket);
      configBd.setUint8(0, 0x80);
      configBd.setUint32(8, 5);
      configPacket.setRange(12, 17, [1, 2, 3, 4, 5]);

      final videoPacket = Uint8List(12 + 3);
      final videoBd = ByteData.sublistView(videoPacket);
      videoBd.setUint8(0, 0x40);
      videoBd.setUint32(4, 12345);
      videoBd.setUint32(8, 3);
      videoPacket.setRange(12, 15, [6, 7, 8]);

      parser
        ..feed(header)
        ..feed(configPacket.sublist(0, 5))
        ..feed(configPacket.sublist(5))
        ..feed(videoPacket);

      final metadata = await metadataFuture;
      expect(metadata.deviceName, 'TestDevice');
      expect(metadata.width, 1080);
      expect(metadata.height, 1920);

      final packets = await packetsFuture;
      expect(packets[0].type, ScrcpyPacketType.configuration);
      expect(packets[0].data, [1, 2, 3, 4, 5]);

      expect(packets[1].type, ScrcpyPacketType.video);
      expect(packets[1].data, [6, 7, 8]);
      expect(packets[1].isKeyFrame, isTrue);
      expect(packets[1].pts, 12345);

      parser.close();
    });
  });
}
