# Text Encoding Tests Design

**Date:** 2026-05-13  
**File under test:** `packages/scrcpy_client/test/send_text_test.dart`

## Goal

Expand the existing control message tests to verify correct UTF-8 encoding for `ScrcpyInjectTextMessage` (type 1) and `ScrcpySetClipboardMessage` (type 9) across ASCII, CJK, emoji, mixed, special characters, and empty strings. Also fix a latent bug in the existing ASCII test that uses Dart's `text.length` / `text.codeUnits` instead of `utf8.encode`-based values.

## Background

Both message types encode text as UTF-8 with a big-endian `uint32` length prefix:

- **Type 1** layout: `type(1) + utf8_len(4) + utf8_bytes`
- **Type 9** layout: `type(1) + sequence(8) + paste(1) + utf8_len(4) + utf8_bytes`

The existing ASCII test passes today because `'hello'.length == utf8.encode('hello').length`. For multi-byte characters (CJK = 3 bytes/char, emoji = 4 bytes/char with Dart length = 2), `text.length` diverges from `utf8.encode(text).length`, so the current assertion style would produce wrong expected values.

## Assertion Style

All tests follow this uniform pattern:

```dart
final bytes = Uint8List.fromList(captured.single);
final bd = ByteData.sublistView(bytes);
final encoded = utf8.encode(text);

expect(bytes.length, headerSize + encoded.length);
expect(bd.getUint32(lenOffset), encoded.length);   // length field = UTF-8 byte count
expect(utf8.decode(bytes.sublist(payloadOffset)), text); // round-trip correctness
```

No raw byte array comparisons for text content — `utf8.decode` round-trip is sufficient and more readable.

## Changes

### Fix existing test

The existing `'text message (type 1) writes 5 + UTF-8 length bytes'` test:
- Replace `5 + text.length` → `5 + utf8.encode(text).length`
- Replace `bd.getUint32(1), text.length` → `bd.getUint32(1), utf8.encode(text).length`
- Replace `captured.single.sublist(5), text.codeUnits` → `utf8.decode(bytes.sublist(5)), text`

### New group: `ScrcpyInjectTextMessage (type 1)`

Wraps the fixed ASCII test plus five new cases. Header = 5 bytes, length offset = 1, payload offset = 5.

| Test | Input | UTF-8 bytes | Total bytes |
|------|-------|-------------|-------------|
| ASCII (fixed) | `'hello'` | 5 | 10 |
| CJK | `'你好'` | 6 | 11 |
| emoji | `'😀'` | 4 | 9 |
| mixed | `'Hi你好😀'` | 12 | 17 |
| special ASCII | `'a\nb\tc'` | 5 | 10 |
| empty string | `''` | 0 | 5 |

For the **special ASCII** test, additionally assert that `bytes[6] == 0x0A` (newline) and `bytes[8] == 0x09` (tab) to confirm control characters pass through unmodified.

### Adjust existing + new group: `ScrcpySetClipboardMessage (type 9)`

Header = 14 bytes, length offset = 10, payload offset = 14. The existing `'你好世界'` test already uses `utf8.decode` — retain it, adjust only if assertion style is inconsistent.

| Test | Input | UTF-8 bytes | Total bytes | Notes |
|------|-------|-------------|-------------|-------|
| ASCII | `'hello'` | 5 | 19 | new |
| CJK (existing) | `'你好世界'` seq=42 | 12 | 26 | adjust style if needed |
| emoji | `'🎉'` | 4 | 18 | new |
| mixed | `'Hi你好🎉'` | 12 | 26 | new |
| special ASCII | `'line1\nline2'` | 11 | 25 | new |
| empty string | `''` | 0 | 14 | new |

`paste` true/false is already covered by a dedicated test — not repeated here.

## Out of Scope

- Strings longer than 65 KB — the protocol layer does no truncation; no value in testing this.
- `paste` flag behavior — already tested independently.
- Device-level injection behavior — this is purely a binary encoding unit test.

## File Changes

Single file: `packages/scrcpy_client/test/send_text_test.dart`

- Fix 1 existing test
- Reorganize into 2 named groups
- Add 10 new test cases (5 per group)
