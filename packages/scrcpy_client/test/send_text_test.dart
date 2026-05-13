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

  group('ScrcpyInjectTextMessage (type 1)', () {
    // Format: type(1) + utf8_len(4 big-endian uint32) + utf8_bytes
    // Length field stores UTF-8 byte count, NOT Dart String.length.

    test('ASCII encodes as 5-byte header + UTF-8 bytes', () {
      final (server, captured) = createServer();
      const text = 'hello';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      expect(captured.length, 1);
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('CJK (3 bytes/char) encodes UTF-8 byte count in length field', () {
      final (server, captured) = createServer();
      const text = '你好';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text); // 6 bytes; text.length == 2
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('emoji (4 bytes/char) encodes UTF-8 byte count in length field', () {
      final (server, captured) = createServer();
      const text = '😀';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text); // 4 bytes; Dart text.length == 2 (surrogate pair)
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('mixed text encodes correct total UTF-8 length', () {
      final (server, captured) = createServer();
      const text = 'Hi你好😀'; // 2 + 6 + 4 = 12 UTF-8 bytes
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
      final (server, captured) = createServer();
      const text = 'a\nb\tc'; // newline + tab
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text); // 5 bytes
      expect(bytes.length, 5 + encoded.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), encoded.length);
      expect(bytes[6], 0x0A); // newline
      expect(bytes[8], 0x09); // tab
      expect(utf8.decode(bytes.sublist(5)), text);
    });

    test('empty string writes 5-byte header only', () {
      final (server, captured) = createServer();
      server.sendControlMessage(const ScrcpyInjectTextMessage(''));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 5);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), 0);
    });
  });

  group('ScrcpySetClipboardMessage (type 9)', () {
    // Format: type(1) + sequence(8 uint64) + paste(1) + utf8_len(4 uint32) + utf8_bytes
    // Header = 14 bytes. paste true/false behavior is tested separately.

    test('ASCII encodes as 14-byte header + UTF-8 bytes', () {
      final (server, captured) = createServer();
      const text = 'hello';
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: text));
      expect(captured.length, 1);
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint64(1), 0);  // default sequence
      expect(bd.getUint8(9), 1);   // default paste = true
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('CJK (3 bytes/char) writes correct UTF-8 byte count', () {
      final (server, captured) = createServer();
      const text = '你好世界';
      server.sendControlMessage(
          const ScrcpySetClipboardMessage(text: text, sequence: 42));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text); // 12 bytes; text.length == 4
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint64(1), 42);
      expect(bd.getUint8(9), 1);
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('emoji (4 bytes/char) encodes UTF-8 byte count in length field', () {
      final (server, captured) = createServer();
      const text = '🎉';
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text); // 4 bytes; Dart text.length == 2
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('mixed text encodes correct total UTF-8 length', () {
      final (server, captured) = createServer();
      const text = 'Hi你好🎉'; // 2 + 6 + 4 = 12 UTF-8 bytes
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
      final (server, captured) = createServer();
      const text = 'line1\nline2';
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text); // 11 bytes
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint32(10), encoded.length);
      expect(utf8.decode(bytes.sublist(14)), text);
    });

    test('empty string writes 14-byte header only', () {
      final (server, captured) = createServer();
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: ''));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 14);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint32(10), 0);
    });
  });
}
