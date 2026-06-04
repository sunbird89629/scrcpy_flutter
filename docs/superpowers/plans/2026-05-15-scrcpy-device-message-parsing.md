# scrcpy Device-to-Host Message Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse scrcpy device→host binary messages from the control socket and expose them as a typed Dart stream, then add a `get_clipboard` MCP tool.

**Architecture:** A new `ScrcpyDeviceMessageParser` (mirrors `ScrcpyStreamParser` pattern) consumes raw bytes from the control socket and emits `ScrcpyDeviceMessage` events. `ScrcpyServer` owns the parser and exposes `Stream<ScrcpyDeviceMessage> deviceMessages`. `ScrcpySession`/`ScrcpySessionImpl`/`ScrcpyViewController` delegate through the stack. The `GetClipboardTool` in `scrcpy_mcp` uses `session.getClipboard()` which sends a `ScrcpyGetClipboardMessage` then awaits the first clipboard event with a 5-second timeout.

**Tech Stack:** Dart 3 sealed classes, `dart:typed_data` ByteData for binary parsing, `dart:async` StreamController.broadcast(), `package:scrcpy_client`, `package:mcp_dart`.

---

## File Map

| File | Action |
|------|--------|
| `packages/scrcpy_client/lib/src/messages/device_message.dart` | Create — sealed `ScrcpyDeviceMessage` class hierarchy |
| `packages/scrcpy_client/lib/src/scrcpy_device_message_parser.dart` | Create — binary parser |
| `packages/scrcpy_client/lib/src/scrcpy_server.dart` | Modify — add `_deviceParser`, `deviceMessages`, `feedDeviceBytes` |
| `packages/scrcpy_client/lib/src/scrcpy_session.dart` | Modify — add `deviceMessages` + `getClipboard()` to interface |
| `packages/scrcpy_client/lib/src/scrcpy_session_impl.dart` | Modify — implement new interface members |
| `packages/scrcpy_client/lib/scrcpy_client.dart` | Modify — export two new files |
| `scrcpy_view/lib/src/scrcpy_view_controller.dart` | Modify — implement new `ScrcpySession` members |
| `scrcpy_mcp/lib/src/tools/get_clipboard.dart` | Create — MCP tool |
| `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart` | Modify — import + register + update prompt |
| `scrcpy_mcp/test/scrcpy_mcp_server_test.dart` | Modify — update `MockScrcpySession`, tool count, add tests |
| `packages/scrcpy_client/test/scrcpy_device_message_parser_test.dart` | Create — parser unit tests |
| `packages/scrcpy_client/test/scrcpy_server_device_messages_test.dart` | Create — server wiring test |

---

## Task 1: `ScrcpyDeviceMessage` sealed class hierarchy + barrel export

**Files:**
- Create: `packages/scrcpy_client/lib/src/messages/device_message.dart`
- Modify: `packages/scrcpy_client/lib/scrcpy_client.dart`

Wire format reference (all multi-byte integers are big-endian, text is UTF-8):
- Type 0 CLIPBOARD: `type(1) | sequence(8) | length(4) | text(length)`
- Type 1 ACK_CLIPBOARD: `type(1) | sequence(8)`
- Type 2 UHID_OUTPUT: `type(1) | id(2) | size(2) | data(size)`

- [ ] **Step 1: Create `device_message.dart`**

```dart
import 'dart:typed_data';

/// Base class for all scrcpy device-to-host messages.
sealed class ScrcpyDeviceMessage {}

/// Type 0: Device clipboard content, sent in response to a
/// [ScrcpyGetClipboardMessage].
final class ScrcpyClipboardDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyClipboardDeviceMessage({
    required this.sequence,
    required this.text,
  });

  final int sequence;
  final String text;
}

/// Type 1: Acknowledgement that a [ScrcpySetClipboardMessage] was applied.
final class ScrcpyAckClipboardDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyAckClipboardDeviceMessage({required this.sequence});

  final int sequence;
}

/// Type 2: HID output data from a UHID device registered on the host.
final class ScrcpyUhidOutputDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyUhidOutputDeviceMessage({required this.id, required this.data});

  final int id;
  final Uint8List data;
}
```

- [ ] **Step 2: Add export to `packages/scrcpy_client/lib/scrcpy_client.dart`**

Open the file and add this line after the existing exports (keep alphabetical order):

```dart
export 'src/messages/device_message.dart';
```

The file should now contain (among others):
```dart
export 'src/messages/control_message.dart';
export 'src/messages/device_message.dart';
export 'src/messages/scrcpy_control_message.dart';
```

- [ ] **Step 3: Verify it compiles**

```bash
cd /Users/hao/ai/mobile/asf_dev/packages/scrcpy_client
dart analyze lib/
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add packages/scrcpy_client/lib/src/messages/device_message.dart \
        packages/scrcpy_client/lib/scrcpy_client.dart
git commit -m "feat(scrcpy_client): add ScrcpyDeviceMessage sealed class hierarchy"
```

---

## Task 2: `ScrcpyDeviceMessageParser` + tests

**Files:**
- Create: `packages/scrcpy_client/lib/src/scrcpy_device_message_parser.dart`
- Create: `packages/scrcpy_client/test/scrcpy_device_message_parser_test.dart`
- Modify: `packages/scrcpy_client/lib/scrcpy_client.dart` (add export)

- [ ] **Step 1: Write the failing tests**

Create `packages/scrcpy_client/test/scrcpy_device_message_parser_test.dart`:

```dart
import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

void main() {
  group('ScrcpyDeviceMessageParser', () {
    late ScrcpyDeviceMessageParser parser;
    late List<ScrcpyDeviceMessage> events;

    setUp(() {
      parser = ScrcpyDeviceMessageParser();
      events = [];
      parser.messages.listen(events.add);
    });

    tearDown(() => parser.close());

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
        () {
      parser.feed(type0Bytes);

      expect(events, hasLength(1));
      final msg = events.first as ScrcpyClipboardDeviceMessage;
      expect(msg.sequence, 1);
      expect(msg.text, 'ok');
    });

    test('type 1: emits ScrcpyAckClipboardDeviceMessage with sequence', () {
      parser.feed(type1Bytes);

      expect(events, hasLength(1));
      final msg = events.first as ScrcpyAckClipboardDeviceMessage;
      expect(msg.sequence, 42);
    });

    test('type 2: emits ScrcpyUhidOutputDeviceMessage with id and data', () {
      parser.feed(type2Bytes);

      expect(events, hasLength(1));
      final msg = events.first as ScrcpyUhidOutputDeviceMessage;
      expect(msg.id, 7);
      expect(msg.data, [0xAB, 0xCD]);
    });

    test('type 0 with non-ASCII text: decodes UTF-8 byte count correctly', () {
      // "你好" = [0xE4,0xBD,0xA0, 0xE5,0xA5,0xBD] — 6 UTF-8 bytes, 2 chars
      final bytes = Uint8List.fromList([
        0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // sequence=1
        0x00, 0x00, 0x00, 0x06, // length=6 (bytes, not chars)
        0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD, // "你好"
      ]);
      parser.feed(bytes);

      expect(events, hasLength(1));
      expect((events.first as ScrcpyClipboardDeviceMessage).text, '你好');
    });

    test('fragmented feed: two feeds produce one event', () {
      // Split the 15-byte type-0 message at index 7
      parser.feed(Uint8List.sublistView(type0Bytes, 0, 7));
      expect(events, isEmpty, reason: 'not enough bytes yet');

      parser.feed(Uint8List.sublistView(type0Bytes, 7));
      expect(events, hasLength(1));
      expect((events.first as ScrcpyClipboardDeviceMessage).text, 'ok');
    });

    test('concatenated messages: two type-1 messages in one feed', () {
      // sequence=1 then sequence=2
      parser.feed(Uint8List.fromList([
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02,
      ]));

      expect(events, hasLength(2));
      expect((events[0] as ScrcpyAckClipboardDeviceMessage).sequence, 1);
      expect((events[1] as ScrcpyAckClipboardDeviceMessage).sequence, 2);
    });

    test('mixed messages: type-0 then type-1 in one feed', () {
      parser.feed(Uint8List.fromList([...type0Bytes, ...type1Bytes]));

      expect(events, hasLength(2));
      expect(events[0], isA<ScrcpyClipboardDeviceMessage>());
      expect(events[1], isA<ScrcpyAckClipboardDeviceMessage>());
    });

    test('unknown type: no crash, no further events emitted', () {
      parser.feed(Uint8List.fromList([0xFF, 0x01, 0x02]));

      expect(events, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/hao/ai/mobile/asf_dev/packages/scrcpy_client
dart test test/scrcpy_device_message_parser_test.dart
```

Expected: Error — `ScrcpyDeviceMessageParser` not found.

- [ ] **Step 3: Create the parser**

Create `packages/scrcpy_client/lib/src/scrcpy_device_message_parser.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:scrcpy_client/src/messages/device_message.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';

/// Parses scrcpy device→host binary messages from the control socket.
///
/// Feed raw bytes via [feed]; parsed messages are emitted on [messages].
/// Wire format (all integers big-endian):
///   Type 0 CLIPBOARD:    type(1) | sequence(8) | length(4) | text(length)
///   Type 1 ACK_CLIPBOARD: type(1) | sequence(8)
///   Type 2 UHID_OUTPUT:  type(1) | id(2) | size(2) | data(size)
class ScrcpyDeviceMessageParser {
  ScrcpyDeviceMessageParser({this.logger = const NoOpScrcpyLogger()});

  final ScrcpyLogger logger;

  Uint8List _buffer = Uint8List(0);
  final _controller = StreamController<ScrcpyDeviceMessage>.broadcast();

  /// Stream of parsed device messages.
  Stream<ScrcpyDeviceMessage> get messages => _controller.stream;

  /// Feed raw bytes from the control socket into the parser.
  void feed(Uint8List data) {
    if (_buffer.isEmpty) {
      _buffer = data;
    } else {
      final merged = Uint8List(_buffer.length + data.length);
      merged.setRange(0, _buffer.length, _buffer);
      merged.setRange(_buffer.length, merged.length, data);
      _buffer = merged;
    }
    _process();
  }

  void _process() {
    var offset = 0;
    outer:
    while (offset < _buffer.length) {
      final type = _buffer[offset];
      switch (type) {
        case 0: // CLIPBOARD
          if (_buffer.length - offset < 13) break outer;
          final hdr = ByteData.sublistView(_buffer, offset + 1, offset + 13);
          final sequence = hdr.getUint64(0);
          final length = hdr.getUint32(8);
          if (_buffer.length - offset < 13 + length) break outer;
          final text = utf8.decode(
            _buffer.sublist(offset + 13, offset + 13 + length),
          );
          _controller.add(
            ScrcpyClipboardDeviceMessage(sequence: sequence, text: text),
          );
          offset += 13 + length;

        case 1: // ACK_CLIPBOARD
          if (_buffer.length - offset < 9) break outer;
          final sequence =
              ByteData.sublistView(_buffer, offset + 1, offset + 9)
                  .getUint64(0);
          _controller
              .add(ScrcpyAckClipboardDeviceMessage(sequence: sequence));
          offset += 9;

        case 2: // UHID_OUTPUT
          if (_buffer.length - offset < 5) break outer;
          final hdr = ByteData.sublistView(_buffer, offset + 1, offset + 5);
          final id = hdr.getUint16(0);
          final size = hdr.getUint16(2);
          if (_buffer.length - offset < 5 + size) break outer;
          final data = Uint8List.fromList(
            _buffer.sublist(offset + 5, offset + 5 + size),
          );
          _controller.add(ScrcpyUhidOutputDeviceMessage(id: id, data: data));
          offset += 5 + size;

        default:
          logger.warn(
            '[ScrcpyDeviceMessageParser] Unknown type: $type — stream desynced',
          );
          offset = _buffer.length; // consume all, stream is unrecoverable
          break outer;
      }
    }

    if (offset > 0) {
      _buffer = offset >= _buffer.length
          ? Uint8List(0)
          : Uint8List.sublistView(_buffer, offset);
    }
  }

  /// Closes the message stream.
  void close() => _controller.close();
}
```

- [ ] **Step 4: Export from barrel**

In `packages/scrcpy_client/lib/scrcpy_client.dart`, add after `device_message.dart`:

```dart
export 'src/messages/device_message.dart';
export 'src/scrcpy_device_message_parser.dart';
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd /Users/hao/ai/mobile/asf_dev/packages/scrcpy_client
dart test test/scrcpy_device_message_parser_test.dart
```

Expected: All 8 tests PASS.

- [ ] **Step 6: Run full package tests to check no regressions**

```bash
dart test
```

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add packages/scrcpy_client/lib/src/scrcpy_device_message_parser.dart \
        packages/scrcpy_client/lib/scrcpy_client.dart \
        packages/scrcpy_client/test/scrcpy_device_message_parser_test.dart
git commit -m "feat(scrcpy_client): add ScrcpyDeviceMessageParser for device-to-host messages"
```

---

## Task 3: Wire `ScrcpyServer.deviceMessages` + tests

**Files:**
- Modify: `packages/scrcpy_client/lib/src/scrcpy_server.dart`
- Create: `packages/scrcpy_client/test/scrcpy_server_device_messages_test.dart`

- [ ] **Step 1: Write failing tests**

Create `packages/scrcpy_client/test/scrcpy_server_device_messages_test.dart`:

```dart
import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:test/test.dart';

import 'utils/server_factory.dart';

void main() {
  group('ScrcpyServer.deviceMessages', () {
    test('emits ScrcpyClipboardDeviceMessage when fed type-0 bytes', () {
      final (server, _) = createTestServer();

      final events = <ScrcpyDeviceMessage>[];
      final sub = server.deviceMessages.listen(events.add);
      addTearDown(sub.cancel);

      // type=0, sequence=1, length=2, text="ok"
      server.feedDeviceBytes(Uint8List.fromList([
        0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x02,
        0x6F, 0x6B,
      ]));

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

      expect(done, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd /Users/hao/ai/mobile/asf_dev/packages/scrcpy_client
dart test test/scrcpy_server_device_messages_test.dart
```

Expected: Error — `feedDeviceBytes` not found, `deviceMessages` not found.

- [ ] **Step 3: Modify `scrcpy_server.dart`**

Open `packages/scrcpy_client/lib/src/scrcpy_server.dart`.

**Add import** (at the top, with existing imports):
```dart
import 'package:meta/meta.dart';
import 'package:scrcpy_client/src/messages/device_message.dart';
import 'package:scrcpy_client/src/scrcpy_device_message_parser.dart';
```

**Add field** after `final ScrcpyStreamParser _parser;`:
```dart
final ScrcpyDeviceMessageParser _deviceParser;
```

**Update constructor** to initialize `_deviceParser`:
```dart
ScrcpyServer({
  required ScrcpyDeviceProvisioner provisioner,
  ScrcpyLogger logger = const NoOpScrcpyLogger(),
  StreamSink<List<int>>? controlSink,
})  : _provisioner = provisioner,
      _log = logger,
      _controlSink = controlSink,
      _parser = ScrcpyStreamParser(logger: logger),
      _deviceParser = ScrcpyDeviceMessageParser(logger: logger);
```

**Add getter** after `Stream<ScrcpyMetadata> get metadata`:
```dart
/// Stream of parsed device→host messages from the control socket.
Stream<ScrcpyDeviceMessage> get deviceMessages => _deviceParser.messages;
```

**Add test helper** after `deviceMessages` getter:
```dart
/// Feeds raw bytes directly into the device message parser.
///
/// For testing only — in production, bytes come from the control socket.
@visibleForTesting
void feedDeviceBytes(Uint8List data) => _deviceParser.feed(data);
```

**Update control socket listener** in `_connectAll()`.

Before (current):
```dart
_controlSubscription = _controlSocket!.listen(
  (data) => _log.debug('[ScrcpyServer] Control data: ${data.length} bytes'),
  onDone: () => _log.warn('[ScrcpyServer] Control socket closed'),
);
```

After:
```dart
_controlSubscription = _controlSocket!.listen(
  (data) => _deviceParser.feed(data),
  onDone: () => _log.warn('[ScrcpyServer] Control socket closed'),
);
```

**Update `stop()`** — add `_deviceParser.close()` after `_parser.close()`:
```dart
Future<void> stop() async {
  _log.info('[ScrcpyServer] Stopping for device: $deviceId');

  await _videoSubscription?.cancel();
  _videoSubscription = null;
  await _controlSubscription?.cancel();
  _controlSubscription = null;
  await _videoSocket?.close();
  _videoSocket = null;
  await _controlSocket?.close();
  _controlSocket = null;

  await _provisioner.depovision();

  _parser.close();
  _deviceParser.close();
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd /Users/hao/ai/mobile/asf_dev/packages/scrcpy_client
dart test test/scrcpy_server_device_messages_test.dart
```

Expected: 2 tests PASS.

- [ ] **Step 5: Run full package tests**

```bash
dart test
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add packages/scrcpy_client/lib/src/scrcpy_server.dart \
        packages/scrcpy_client/test/scrcpy_server_device_messages_test.dart
git commit -m "feat(scrcpy_client): wire ScrcpyDeviceMessageParser into ScrcpyServer control socket"
```

---

## Task 4: Extend `ScrcpySession` interface + `ScrcpySessionImpl`

**Files:**
- Modify: `packages/scrcpy_client/lib/src/scrcpy_session.dart`
- Modify: `packages/scrcpy_client/lib/src/scrcpy_session_impl.dart`

- [ ] **Step 1: Add two members to `ScrcpySession` abstract interface**

Open `packages/scrcpy_client/lib/src/scrcpy_session.dart`.

Add import at top:
```dart
import 'dart:async';

import 'package:scrcpy_client/src/messages/device_message.dart';
import 'package:scrcpy_client/src/messages/scrcpy_control_message.dart';
```

Add two members after `void injectText(String text);`:
```dart
/// Stream of parsed device→host messages received on the control socket.
Stream<ScrcpyDeviceMessage> get deviceMessages;

/// Reads the device clipboard.
///
/// Sends a [ScrcpyGetClipboardMessage] then waits for the device to reply
/// with a [ScrcpyClipboardDeviceMessage]. Throws [TimeoutException] if no
/// reply arrives within [timeout].
Future<String> getClipboard({
  Duration timeout = const Duration(seconds: 5),
});
```

The full updated interface:
```dart
import 'dart:async';

import 'package:scrcpy_client/src/messages/device_message.dart';
import 'package:scrcpy_client/src/messages/scrcpy_control_message.dart';

/// Abstraction over a scrcpy mirroring session.
///
/// Pure-Dart contract: no Flutter or HTTP-proxy concerns.
/// Flutter consumers use a separate ScrcpyViewController which adds
/// proxy/WebSocket server management on top.
abstract class ScrcpySession {
  bool get isConnected;
  int? get videoWidth;
  int? get videoHeight;
  Future<void> start(String deviceId);
  Future<void> stop();
  void sendControlMessage(ScrcpyControlMessage message);
  void injectText(String text);
  Stream<ScrcpyDeviceMessage> get deviceMessages;
  Future<String> getClipboard({Duration timeout = const Duration(seconds: 5)});
}
```

- [ ] **Step 2: Implement in `ScrcpySessionImpl`**

Open `packages/scrcpy_client/lib/src/scrcpy_session_impl.dart`.

Add import at top (with existing imports):
```dart
import 'dart:async';

import 'package:scrcpy_client/src/messages/device_message.dart';
```

Add after `void injectText(String text)` implementation:
```dart
@override
Stream<ScrcpyDeviceMessage> get deviceMessages =>
    _server?.deviceMessages ?? Stream<ScrcpyDeviceMessage>.empty();

@override
Future<String> getClipboard({
  Duration timeout = const Duration(seconds: 5),
}) async {
  sendControlMessage(const ScrcpyGetClipboardMessage());
  return deviceMessages
      .whereType<ScrcpyClipboardDeviceMessage>()
      .first
      .timeout(timeout)
      .then((m) => m.text);
}
```

`ScrcpyGetClipboardMessage` is already imported via `control_message.dart`.

- [ ] **Step 3: Analyze for compile errors**

```bash
cd /Users/hao/ai/mobile/asf_dev/packages/scrcpy_client
dart analyze lib/
```

Expected: No errors.

- [ ] **Step 4: Run tests**

```bash
dart test
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add packages/scrcpy_client/lib/src/scrcpy_session.dart \
        packages/scrcpy_client/lib/src/scrcpy_session_impl.dart
git commit -m "feat(scrcpy_client): add deviceMessages and getClipboard() to ScrcpySession"
```

---

## Task 5: Update `ScrcpyViewController`

**Files:**
- Modify: `scrcpy_view/lib/src/scrcpy_view_controller.dart`

`ScrcpyViewController` implements `ScrcpySession`. Adding members to that interface means it must implement them.

- [ ] **Step 1: Analyze to see missing implementations**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_view
dart analyze lib/
```

Expected: Errors — `deviceMessages` and `getClipboard` not implemented.

- [ ] **Step 2: Add import**

Open `scrcpy_view/lib/src/scrcpy_view_controller.dart`.

The file already imports `package:scrcpy_client/scrcpy_client.dart` which now exports `device_message.dart`. No new imports needed. Add `dart:async` if not already present (check top of file).

If `dart:async` is not already imported, add it:
```dart
import 'dart:async';
```

- [ ] **Step 3: Add the two implementations**

In `ScrcpyViewController`, after `void injectText(String text)` implementation, add:

```dart
@override
Stream<ScrcpyDeviceMessage> get deviceMessages =>
    _impl?.deviceMessages ?? Stream<ScrcpyDeviceMessage>.empty();

@override
Future<String> getClipboard({
  Duration timeout = const Duration(seconds: 5),
}) =>
    _impl?.getClipboard(timeout: timeout) ??
    Future.error(StateError('Not connected'));
```

- [ ] **Step 4: Analyze**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_view
dart analyze lib/
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_view/lib/src/scrcpy_view_controller.dart
git commit -m "feat(scrcpy_view): implement deviceMessages and getClipboard() in ScrcpyViewController"
```

---

## Task 6: `GetClipboardTool` + update `MockScrcpySession` + server registration + tests

**Files:**
- Create: `scrcpy_mcp/lib/src/tools/get_clipboard.dart`
- Modify: `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Write failing tests**

Open `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`.

**Update `MockScrcpySession`**: add the two new interface members (the class will fail to compile without them). Add after `void injectText(String text) {}`:

```dart
Future<String> Function()? getClipboardImpl;

@override
Stream<ScrcpyDeviceMessage> get deviceMessages =>
    Stream<ScrcpyDeviceMessage>.empty();

@override
Future<String> getClipboard({
  Duration timeout = const Duration(seconds: 5),
}) =>
    getClipboardImpl?.call() ?? Future.value('');
```

**Update tool count** in `'advertises 19 tools after connect'` test — change `19` to `20` and add `'get_clipboard'` to the `containsAll` list:

```dart
test('advertises 20 tools after connect', () async {
  final env = _TestEnv();
  await env.connect();

  final tools = await env.client.listTools();
  final names = tools.tools.map((t) => t.name).toSet();

  expect(
    names,
    containsAll([
      'list_devices',
      'start_mirroring',
      'stop_mirroring',
      'inject_key',
      'inject_touch',
      'inject_text',
      'inject_scroll',
      'inject_swipe',
      'take_screenshot',
      'press_back',
      'set_screen_power',
      'rotate_device',
      'set_clipboard',
      'get_clipboard',
      'expand_notification_panel',
      'expand_settings_panel',
      'collapse_panels',
      'set_torch',
      'camera_zoom',
      'start_app',
    ]),
  );
});
```

**Add `get_clipboard` tests** after the `camera_zoom` tests (before `'ScrcpyMcpServer — resources'`):

```dart
test('get_clipboard without active session returns error', () async {
  final env = _TestEnv();
  await env.connect();

  final result = await env.client.callTool(
    const CallToolRequest(name: 'get_clipboard'),
  );

  expect(result.isError, isTrue);
});

test('get_clipboard returns clipboard text', () async {
  final env = _TestEnv();
  await env.connect();
  await env.client.callTool(
    const CallToolRequest(
        name: 'start_mirroring', arguments: {'device_id': 'device1'}),
  );
  env.session.getClipboardImpl = () async => 'copied text';

  final result = await env.client.callTool(
    const CallToolRequest(name: 'get_clipboard'),
  );

  expect(result.isError, isFalse);
  expect(textContent(result), 'copied text');
});

test('get_clipboard returns error on timeout', () async {
  final env = _TestEnv();
  await env.connect();
  await env.client.callTool(
    const CallToolRequest(
        name: 'start_mirroring', arguments: {'device_id': 'device1'}),
  );
  env.session.getClipboardImpl = () => Future.error(
    TimeoutException('timeout', const Duration(seconds: 5)),
  );

  final result = await env.client.callTool(
    const CallToolRequest(name: 'get_clipboard'),
  );

  expect(result.isError, isTrue);
  expect(textContent(result), contains('Timed out'));
});
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp
dart test test/scrcpy_mcp_server_test.dart
```

Expected: Errors — `MockScrcpySession` missing interface members (compile error), `get_clipboard` tool not registered.

- [ ] **Step 3: Create `get_clipboard.dart`**

Create `scrcpy_mcp/lib/src/tools/get_clipboard.dart`:

```dart
import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

/// Reads the current text content of the device clipboard.
///
/// Sends a GetClipboard request to the device via scrcpy and waits up to
/// 5 seconds for the device to respond with clipboard contents.
class GetClipboardTool extends McpTool {
  GetClipboardTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'get_clipboard';

  @override
  String get description => 'Read the current text content of the device clipboard.';

  @override
  ToolInputSchema get inputSchema => JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    try {
      final text = await _session.getClipboard();
      return CallToolResult.fromContent([TextContent(text: text)]);
    } on TimeoutException {
      return CallToolResult.fromContent(
        [TextContent(text: 'Timed out waiting for clipboard response.')],
        isError: true,
      );
    }
  }
}
```

- [ ] **Step 4: Register in `scrcpy_mcp_server.dart`**

Open `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`.

**Add import** (keep imports alphabetically sorted by file name):
```dart
import 'tools/get_clipboard.dart' show GetClipboardTool;
```

Place it between `tools/expand_settings_panel.dart` and `tools/inject_key.dart`:
```dart
import 'tools/get_clipboard.dart' show GetClipboardTool;
```

**Add to tool list** in `_registerTools()`, after `SetClipboardTool(_session),`:
```dart
GetClipboardTool(_session),
```

**Update `_getControlDevicePrompt`** — change the `set_clipboard` line to include `get_clipboard`:
```dart
'- set_clipboard, get_clipboard\n'
```

Find the existing line:
```dart
'- set_clipboard\n'
```
Replace with:
```dart
'- set_clipboard, get_clipboard\n'
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp
dart test test/scrcpy_mcp_server_test.dart
```

Expected: All tests PASS (including 3 new `get_clipboard` tests).

- [ ] **Step 6: Run full monorepo tests**

```bash
cd /Users/hao/ai/mobile/asf_dev
melos run test
```

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_mcp/lib/src/tools/get_clipboard.dart \
        scrcpy_mcp/lib/src/scrcpy_mcp_server.dart \
        scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add get_clipboard tool backed by device-to-host message parsing"
```
