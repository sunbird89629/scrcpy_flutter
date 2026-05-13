# Text Encoding Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand `send_text_test.dart` to verify UTF-8 encoding correctness for `ScrcpyInjectTextMessage` and `ScrcpySetClipboardMessage` across ASCII, CJK, emoji, mixed, special characters, and empty strings; fix a latent assertion bug in the existing ASCII test.

**Architecture:** All changes are confined to one test file. No new source files. Since the production encoding code (`control_message.dart`) is already correct, every test written should pass immediately — this is regression coverage, not TDD driving new behavior.

**Tech Stack:** Dart `test` package, `dart:convert` (`utf8`), `dart:typed_data`.

---

## File Map

| Action | Path |
|--------|------|
| Modify | `packages/scrcpy_client/test/send_text_test.dart` |

---

### Task 1: Fix type-1 ASCII test and add multi-byte tests

Move the existing ASCII test out of the catch-all group into a dedicated `ScrcpyInjectTextMessage (type 1)` group, fix its assertion style, and add five new cases.

**Files:**
- Modify: `packages/scrcpy_client/test/send_text_test.dart`

- [ ] **Step 1: Replace the existing type-1 test and add the new group**

Open `packages/scrcpy_client/test/send_text_test.dart`.

Remove the existing test block inside `group('sendControlMessage via injected sink')`:
```dart
    test('text message (type 1) writes 5 + UTF-8 length bytes', () {
      final (server, captured) = createServer();
      const text = 'hello';
      server.sendControlMessage(const ScrcpyInjectTextMessage(text));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 5 + text.length);
      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), text.length);
      expect(captured.single.sublist(5), text.codeUnits);
    });
```

After the closing `});` of the existing group, add a new sibling group:

```dart
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
```

- [ ] **Step 2: Run the new group and verify all 6 tests pass**

```bash
cd /Users/hao/ai/mobile/asf_dev/packages/scrcpy_client && \
  flutter test test/send_text_test.dart --name "ScrcpyInjectTextMessage" -v
```

Expected: 6 tests, all PASS. If any fail, the production encoding in `lib/src/control_message.dart:76-85` is the source of truth — re-check the test arithmetic.

- [ ] **Step 3: Commit**

```bash
git add packages/scrcpy_client/test/send_text_test.dart
git commit -m "test(scrcpy_client): expand ScrcpyInjectTextMessage encoding tests"
```

---

### Task 2: Adjust type-9 CJK test and add multi-byte tests

Replace the existing `ScrcpySetClipboardMessage` test with one that uses `utf8.encode`-style assertions, and add five new cases alongside it in a dedicated group.

**Files:**
- Modify: `packages/scrcpy_client/test/send_text_test.dart`

- [ ] **Step 1: Remove the existing type-9 text test and add the new group**

Remove this block from `group('sendControlMessage via injected sink')`:
```dart
    test('set-clipboard message (type 9) writes 14 + UTF-8 bytes', () {
      final (server, captured) = createServer();
      const text = '你好世界';
      server.sendControlMessage(
          const ScrcpySetClipboardMessage(text: text, sequence: 42));
      expect(captured.length, 1);
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 14 + 12);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint64(1), 42);
      expect(bd.getUint8(9), 1);
      expect(bd.getUint32(10), 12);
      expect(utf8.decode(bytes.sublist(14)), text);
    });
```

After the closing `});` of the type-1 group, add:

```dart
  group('ScrcpySetClipboardMessage (type 9)', () {
    // Format: type(1) + sequence(8 uint64) + paste(1) + utf8_len(4 uint32) + utf8_bytes
    // Header = 14 bytes. paste true/false behavior is tested separately.

    test('ASCII encodes as 14-byte header + UTF-8 bytes', () {
      final (server, captured) = createServer();
      const text = 'hello';
      server.sendControlMessage(const ScrcpySetClipboardMessage(text: text));
      final bytes = Uint8List.fromList(captured.single);
      final bd = ByteData.sublistView(bytes);
      final encoded = utf8.encode(text);
      expect(bytes.length, 14 + encoded.length);
      expect(bd.getUint8(0), 9);
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
```

- [ ] **Step 2: Run the full test file and verify all tests pass**

```bash
cd /Users/hao/ai/mobile/asf_dev/packages/scrcpy_client && \
  flutter test test/send_text_test.dart -v
```

Expected output: all tests PASS. The total count should be:
- `sendControlMessage via injected sink`: 5 tests (touch, keycode, scroll, paste=false, back-or-screen-on)
- `ScrcpyInjectTextMessage (type 1)`: 6 tests
- `ScrcpySetClipboardMessage (type 9)`: 6 tests
- Total: 17 tests

- [ ] **Step 3: Commit**

```bash
git add packages/scrcpy_client/test/send_text_test.dart
git commit -m "test(scrcpy_client): expand ScrcpySetClipboardMessage encoding tests"
```
