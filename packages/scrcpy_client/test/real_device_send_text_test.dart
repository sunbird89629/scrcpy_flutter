@Tags(['real-device'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_server.dart';
import 'package:test/test.dart';

import 'utils/real_adb.dart';
import 'utils/server_factory.dart';

void main() {
  group('ScrcpyInjectTextMessage (type 1)', () {
    // Length field stores UTF-8 byte count, NOT Dart String.length.

    late RealAdb adb;
    late String realDeviceId;
    late Uint8List realJarBytes;

    setUpAll(() async {
      adb = RealAdb();
      final devices = await adb.getDevices();
      if (devices.isEmpty) {
        throw StateError('No ADB devices connected — plug in a device first');
      }
      realDeviceId = devices.first;
      realJarBytes = await File(
        'assets/scrcpy-server-v${ScrcpyServer.serverVersion}',
      ).readAsBytes();
    });

    test('ASCII encodes as 5-byte header + UTF-8 bytes', () async {
      final (server, captured) = createRealServer(
        deviceId: realDeviceId,
        jarBytes: realJarBytes,
      );
      addTearDown(server.stop);
      const text = 'hello';
      await server.start();
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      adb.takeScreenshot(realDeviceId);
      expect(captured.length, 1);
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      // expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('CJK (3 bytes/char) encodes UTF-8 byte count in length field', () {
      final (server, captured) = createTestServer();
      const text = '你好';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('emoji (4 bytes/char) encodes UTF-8 byte count in length field', () {
      final (server, captured) = createTestServer();
      const text = '😀';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded =
          utf8.encode(text); // Dart text.length == 2 (surrogate pair)
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('mixed text encodes correct total UTF-8 length', () {
      final (server, captured) = createTestServer();
      const text = 'Hi你好😀';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('special ASCII characters pass through unmodified', () {
      final (server, captured) = createTestServer();
      const text = 'a\nb\tc';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      expect(bytes[6], 0x0A); // newline
      expect(bytes[8], 0x09); // tab
      expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('empty string writes 5-byte header only', () {
      final (server, captured) = createTestServer();
      server.sendControlMessage(const ScrcpyInjectTextMessage(''));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 5);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), 0);
    });
  });

  group('ScrcpySetClipboardMessage (type 9)', () {
    // paste true/false behavior is tested separately.

    test('ASCII encodes as 14-byte header + UTF-8 bytes', () {
      final (server, captured) = createTestServer();
      const text = 'hello';
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: text));
      expect(captured.length, 1);
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint64(1), 0); // default sequence
      expect(bd.getUint8(9), 1); // default paste = true
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('CJK (3 bytes/char) writes correct UTF-8 byte count', () {
      final (server, captured) = createTestServer();
      const text = '你好世界';
      server.sendControlMessage(
          const ScrcpySetClipboardMessage(text: text, sequence: 42));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint64(1), 42);
      expect(bd.getUint8(9), 1);
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('emoji (4 bytes/char) encodes UTF-8 byte count in length field', () {
      final (server, captured) = createTestServer();
      const text = '🎉';
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded =
          utf8.encode(text); // Dart text.length == 2 (surrogate pair)
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('mixed text encodes correct total UTF-8 length', () {
      final (server, captured) = createTestServer();
      const text = 'Hi你好🎉';
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('special ASCII characters pass through unmodified', () {
      final (server, captured) = createTestServer();
      const text = 'line1\nline2';
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('empty string writes 14-byte header only', () {
      final (server, captured) = createTestServer();
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: ''));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 14);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint32(10), 0);
    });
  });
}
