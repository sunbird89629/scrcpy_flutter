# scrcpy_client — Device-to-Host Message Parsing

**Date:** 2026-05-15
**Package:** `scrcpy_client`, `scrcpy_mcp`
**Status:** Approved

---

## Goal

Parse device→host binary messages arriving on the scrcpy control socket and expose them as a typed Dart stream. Add a `get_clipboard` MCP tool that uses the new stream to read clipboard content from the device.

---

## Out of Scope

- Sending UHID input messages (types 12–14): host→device direction, separate concern.
- Parsing video-stream device messages: those travel on the video socket and are handled by `ScrcpyStreamParser`.

---

## Wire Protocol

All messages arrive on the control socket (device→host direction):

| Type | Name | Layout |
|------|------|--------|
| 0 | CLIPBOARD | `type(1) \| sequence(8) \| length(4) \| text(length)` |
| 1 | ACK_CLIPBOARD | `type(1) \| sequence(8)` |
| 2 | UHID_OUTPUT | `type(1) \| id(2) \| size(2) \| data(size)` |

All multi-byte integers are big-endian. Text is UTF-8.

---

## New Files

### `packages/scrcpy_client/lib/src/messages/device_message.dart`

Sealed class hierarchy — one subclass per message type:

```dart
sealed class ScrcpyDeviceMessage {}

final class ScrcpyClipboardDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyClipboardDeviceMessage({required this.sequence, required this.text});
  final int sequence;
  final String text;
}

final class ScrcpyAckClipboardDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyAckClipboardDeviceMessage({required this.sequence});
  final int sequence;
}

final class ScrcpyUhidOutputDeviceMessage extends ScrcpyDeviceMessage {
  const ScrcpyUhidOutputDeviceMessage({required this.id, required this.data});
  final int id;
  final Uint8List data;
}
```

`sealed` enables exhaustive `switch` in consumers.

### `packages/scrcpy_client/lib/src/scrcpy_device_message_parser.dart`

Binary parser following the same pattern as `ScrcpyStreamParser`:

- `Uint8List _buffer` accumulates incoming bytes.
- `feed(Uint8List data)` appends to `_buffer` then calls `_process()`.
- `_process()` loops:
  - Peeks `_buffer[0]` to determine message type.
  - Checks minimum byte count before reading:
    - type 0: needs ≥ 13 bytes for header, then 13 + `length` total.
    - type 1: needs ≥ 9 bytes.
    - type 2: needs ≥ 5 bytes for header, then 5 + `size` total.
  - Exits loop early if not enough bytes (waits for next `feed` call).
  - On unknown type: logs a warning and breaks (stream is unrecoverable after desync).
  - On success: emits typed message, advances `_buffer`.
- Exposes `Stream<ScrcpyDeviceMessage> get messages` backed by a `StreamController.broadcast()`.
- `close()` closes the controller.

Constructor accepts `ScrcpyLogger` (defaults to `NoOpScrcpyLogger`).

---

## Modified Files

### `packages/scrcpy_client/lib/src/scrcpy_server.dart`

- Add `final ScrcpyDeviceMessageParser _deviceParser` (constructed in constructor or `_connectAll`).
- Expose `Stream<ScrcpyDeviceMessage> get deviceMessages => _deviceParser.messages`.
- In `_connectAll()`, replace the control socket listener body:
  ```dart
  _controlSubscription = _controlSocket!.listen(
    (data) => _deviceParser.feed(data),
    onDone: () => _log.warn('[ScrcpyServer] Control socket closed'),
  );
  ```
- In `stop()`, add `_deviceParser.close()`.

### `packages/scrcpy_client/lib/src/scrcpy_session.dart`

Add two members to the `ScrcpySession` abstract interface:

```dart
Stream<ScrcpyDeviceMessage> get deviceMessages;
Future<String> getClipboard();
```

### `packages/scrcpy_client/lib/src/scrcpy_session_impl.dart`

Implement both new interface members:

```dart
@override
Stream<ScrcpyDeviceMessage> get deviceMessages => _server.deviceMessages;

@override
Future<String> getClipboard() async {
  sendControlMessage(ScrcpyGetClipboardMessage());
  return deviceMessages
      .whereType<ScrcpyClipboardDeviceMessage>()
      .first
      .timeout(const Duration(seconds: 5))
      .then((m) => m.text);
}
```

### `packages/scrcpy_client/lib/scrcpy_client.dart`

Export `device_message.dart` and `scrcpy_device_message_parser.dart`.

### `scrcpy_view/lib/src/scrcpy_view_controller.dart`

Implement the two new `ScrcpySession` interface members by delegating to the internal `ScrcpyServer`:

```dart
@override
Stream<ScrcpyDeviceMessage> get deviceMessages => _server.deviceMessages;

@override
Future<String> getClipboard() async {
  sendControlMessage(ScrcpyGetClipboardMessage());
  return deviceMessages
      .whereType<ScrcpyClipboardDeviceMessage>()
      .first
      .timeout(const Duration(seconds: 5))
      .then((m) => m.text);
}
```

### `scrcpy_mcp/lib/src/tools/get_clipboard.dart` (new)

```dart
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
  Future<CallToolResult> execute(Map<String, dynamic> args, RequestHandlerExtra extra) async {
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

### `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`

- Add import for `get_clipboard.dart`.
- Register `GetClipboardTool(_session)` in the tool list.
- Add `get_clipboard` to the `control_device` prompt's tool list.

---

## Testing

### Unit tests — `ScrcpyDeviceMessageParser`

File: `packages/scrcpy_client/test/device_message_parser_test.dart`

- type 0: single feed with exact bytes → emits `ScrcpyClipboardDeviceMessage` with correct sequence and text.
- type 0: ASCII, CJK, emoji — UTF-8 byte count in `length` field.
- type 1: exact bytes → emits `ScrcpyAckClipboardDeviceMessage` with correct sequence.
- type 2: exact bytes → emits `ScrcpyUhidOutputDeviceMessage` with correct id and data.
- Fragmented feed: split across two `feed()` calls → still emits correct message.
- Concatenated feed: two messages in one `feed()` call → emits two events in order.
- Unknown type: logs warning, no crash (stream goes silent).

### Unit tests — `ScrcpySessionImpl.getClipboard()`

File: `packages/scrcpy_client/test/scrcpy_session_impl_test.dart` (extend existing)

- `getClipboard()` sends `ScrcpyGetClipboardMessage` then returns text from first clipboard event.
- `getClipboard()` throws `TimeoutException` if no clipboard event arrives within 5 s.

### Unit tests — `GetClipboardTool`

File: `scrcpy_mcp/test/tools/get_clipboard_test.dart`

- Not connected → returns `notConnectedResult`.
- Session returns text → tool returns that text.
- Session times out → tool returns error result.

No real-device tests required — parser correctness is fully verifiable with synthetic byte arrays.

---

## File Change Summary

| File | Change |
|------|--------|
| `packages/scrcpy_client/lib/src/messages/device_message.dart` | New |
| `packages/scrcpy_client/lib/src/scrcpy_device_message_parser.dart` | New |
| `packages/scrcpy_client/lib/src/scrcpy_server.dart` | Wire parser into control socket |
| `packages/scrcpy_client/lib/src/scrcpy_session.dart` | Add `deviceMessages` + `getClipboard()` |
| `packages/scrcpy_client/lib/src/scrcpy_session_impl.dart` | Implement new interface members |
| `packages/scrcpy_client/lib/scrcpy_client.dart` | Export new files |
| `scrcpy_view/lib/src/scrcpy_view_controller.dart` | Implement new `ScrcpySession` members |
| `scrcpy_mcp/lib/src/tools/get_clipboard.dart` | New |
| `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart` | Register `GetClipboardTool`, update prompt |
