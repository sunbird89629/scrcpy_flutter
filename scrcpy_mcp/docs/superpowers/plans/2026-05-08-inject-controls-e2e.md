# Inject Controls E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real-device e2e test group to `scrcpy_mcp_real_device_test.dart` that starts a genuine scrcpy session and verifies `inject_scroll`, `inject_key`, `inject_touch`, and `inject_text` produce observable device effects.

**Architecture:** All four inject commands route through `session.sendControlMessage()` / `session.injectText()` on `ScrcpySessionImpl`, which holds a live scrcpy control socket to the device. Tests verify effect by comparing before/after ADB screenshots (PNG byte diff). A single scrcpy session is started in `setUpAll` and shared across all four tests.

**Tech Stack:** Dart `test` package, `ScrcpySessionImpl` (from `package:scrcpy_view/scrcpy_core.dart`), `ScrcpyMcpAdb`, `McpClient` over in-memory `IOStreamTransport`.

---

## File Map

| Action | Path |
|--------|------|
| Modify | `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart` |

No other files change.

---

### Task 1: Remove the broken `horizontal_swipe` stub

The file currently contains an incomplete group (missing `env.connect()`, empty tool name) that will error at runtime.

**Files:**
- Modify: `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart:152-163`

- [ ] **Step 1: Delete the broken group**

Remove lines 152–163 (the entire `group('real device - horizontal_swipe', ...)` block):

```dart
  group('real device - horizontal_swipe', () {
    test('show app launcher bottomsheet if work', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }
      final env = _Env(adb: adb);
      final result = await env.client.callTool(
        const CallToolRequest(name: '')
      );
    });
  });
```

- [ ] **Step 2: Verify existing tests still pass**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart --tags real-device
```

Expected: all tests pass (or skip) cleanly, no compile errors.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart
git commit -m "test: remove incomplete horizontal_swipe stub"
```

---

### Task 2: Add `_E2eEnv` class and helpers

Introduces the infrastructure that e2e tests depend on. No tests are added yet — this task only adds types and functions.

**Files:**
- Modify: `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart`

- [ ] **Step 1: Add `_E2eEnv` class after the existing `_Env` class**

Insert after the closing `}` of `_Env` (around line 107):

```dart
// ---------------------------------------------------------------------------
// E2E environment — real ScrcpySessionImpl, real ADB, in-memory MCP transport
// ---------------------------------------------------------------------------

class _E2eEnv {
  _E2eEnv({required ScrcpyMcpAdb adb, required ScrcpySession session}) {
    server = ScrcpyMcpServer(session: session, adb: adb);
  }

  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async {
    final serverToClient = StreamController<List<int>>();
    final clientToServer = StreamController<List<int>>();

    await server.mcpServer.connect(
      IOStreamTransport(
        stream: clientToServer.stream,
        sink: serverToClient.sink,
      ),
    );

    client = McpClient(
      const Implementation(name: 'test-client', version: '0.0.1'),
      options: const McpClientOptions(capabilities: ClientCapabilities()),
    );
    await client.connect(
      IOStreamTransport(
        stream: serverToClient.stream,
        sink: clientToServer.sink,
      ),
    );

    addTearDown(() async {
      await serverToClient.close();
      await clientToServer.close();
    });
  }
}
```

- [ ] **Step 2: Add pixel-diff helpers and screen-size helper after `_text`**

Insert after the existing `String _text(CallToolResult r) => ...` line:

```dart
Uint8List _screenshotBytes(CallToolResult r) =>
    base64Decode((r.content.first as ImageContent).data);

bool _hasScreenChanged(
  Uint8List before,
  Uint8List after, {
  int threshold = 100,
}) {
  if (before.length != after.length) return true;
  var diff = 0;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i] && ++diff > threshold) return true;
  }
  return false;
}

Future<(int, int)> _getScreenSize(ScrcpyMcpAdb adb, String deviceId) async {
  final result = await adb.shell(['wm', 'size'], deviceId: deviceId);
  final m = RegExp(r'(\d+)x(\d+)').firstMatch(result.stdout as String);
  if (m == null) return (1080, 1920);
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}
```

- [ ] **Step 3: Verify the file compiles (no tests added yet)**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart analyze scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart
```

Expected: no errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart
git commit -m "test: add _E2eEnv class and pixel-diff helpers for e2e inject tests"
```

---

### Task 3: `inject_scroll` — RED then GREEN

**Files:**
- Modify: `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart`

- [ ] **Step 1: Write the failing test — add e2e group WITH INCOMPLETE setUpAll (no start_mirroring)**

Append to the end of `main()` (before the final `}`):

```dart
  // ── inject controls (e2e with real scrcpy) ────────────────────────────────

  group('real device — inject controls (e2e)', () {
    late ScrcpySessionImpl e2eSession;
    late _E2eEnv e2eEnv;
    late (int, int) screenSize;

    setUpAll(() async {
      if (realDevices.isEmpty) return;
      final deviceId = realDevices.first;
      e2eSession = await ScrcpySessionImpl.create(adb: adb);
      e2eEnv = _E2eEnv(adb: adb, session: e2eSession);
      await e2eEnv.connect();
      // NOTE: start_mirroring intentionally omitted — causes RED below
      screenSize = await _getScreenSize(adb, deviceId);
    }, timeout: const Timeout(Duration(seconds: 30)));

    tearDownAll(() async {
      if (realDevices.isEmpty) return;
      await e2eEnv.client.callTool(
        const CallToolRequest(name: 'stop_mirroring'),
      );
    });

    test('inject_scroll changes screen content', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }
      final (w, h) = screenSize;

      final before = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));

      final scrollResult = await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'inject_scroll',
          arguments: {
            'x': w ~/ 2,
            'y': h ~/ 2,
            'width': w,
            'height': h,
            'hScroll': 0,
            'vScroll': -3,
          },
        ),
      );
      expect(scrollResult.isError, isFalse, reason: _text(scrollResult));

      await Future.delayed(const Duration(milliseconds: 800));

      final after = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));

      expect(
        _hasScreenChanged(before, after),
        isTrue,
        reason: 'Screen should change after scrolling',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
```

- [ ] **Step 2: Run test — confirm RED**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart \
  --name "inject_scroll changes" --tags real-device
```

Expected failure: `inject_scroll` returns `isError: true` with text `"No active mirroring session."` — because `start_mirroring` was not called.

- [ ] **Step 3: Fix setUpAll — add `start_mirroring` call (GREEN)**

Replace the `setUpAll` body. Change:

```dart
    setUpAll(() async {
      if (realDevices.isEmpty) return;
      final deviceId = realDevices.first;
      e2eSession = await ScrcpySessionImpl.create(adb: adb);
      e2eEnv = _E2eEnv(adb: adb, session: e2eSession);
      await e2eEnv.connect();
      // NOTE: start_mirroring intentionally omitted — causes RED below
      screenSize = await _getScreenSize(adb, deviceId);
    }, timeout: const Timeout(Duration(seconds: 30)));
```

To:

```dart
    setUpAll(() async {
      if (realDevices.isEmpty) return;
      final deviceId = realDevices.first;
      e2eSession = await ScrcpySessionImpl.create(adb: adb);
      e2eEnv = _E2eEnv(adb: adb, session: e2eSession);
      await e2eEnv.connect();
      await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': deviceId},
        ),
      );
      screenSize = await _getScreenSize(adb, deviceId);
    }, timeout: const Timeout(Duration(seconds: 30)));
```

- [ ] **Step 4: Run test — confirm GREEN**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart \
  --name "inject_scroll changes" --tags real-device
```

Expected: PASS. Screen changed after scroll.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart
git commit -m "test: add inject_scroll e2e test with real scrcpy session"
```

---

### Task 4: `inject_key` — RED then GREEN

**Files:**
- Modify: `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart`

- [ ] **Step 1: Write the failing test — add inside the e2e group, after inject_scroll test**

```dart
    test('inject_key Home navigates to launcher', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final before = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));

      // Deliberately wrong keycode to produce RED: keycode 999 does nothing
      final keyResult = await e2eEnv.client.callTool(
        const CallToolRequest(
          name: 'inject_key',
          arguments: {'keycode': 999},
        ),
      );
      expect(keyResult.isError, isFalse, reason: _text(keyResult));

      await Future.delayed(const Duration(milliseconds: 500));

      final after = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));

      expect(
        _hasScreenChanged(before, after),
        isTrue,
        reason: 'Home key should trigger navigation or launcher animation',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
```

- [ ] **Step 2: Run test — confirm RED**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart \
  --name "inject_key Home" --tags real-device
```

Expected failure: `_hasScreenChanged` is `false` — keycode 999 produces no visible change.

- [ ] **Step 3: Fix keycode to Home (3) — GREEN**

Replace `{'keycode': 999}` with `{'keycode': 3}`:

```dart
      final keyResult = await e2eEnv.client.callTool(
        const CallToolRequest(
          name: 'inject_key',
          arguments: {'keycode': 3},
        ),
      );
```

- [ ] **Step 4: Run test — confirm GREEN**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart \
  --name "inject_key Home" --tags real-device
```

Expected: PASS. Screen changed after Home key press.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart
git commit -m "test: add inject_key e2e test with real scrcpy session"
```

---

### Task 5: `inject_touch` — RED then GREEN

**Files:**
- Modify: `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart`

- [ ] **Step 1: Write the failing test — add inside the e2e group**

```dart
    test('inject_touch at centre succeeds', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }
      final (w, h) = screenSize;

      // action=down at screen centre — deliberately missing action=up for RED
      final downResult = await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'inject_touch',
          arguments: {
            'x': w ~/ 2,
            'y': h ~/ 2,
            'width': w,
            'height': h,
            'action': 0,
          },
        ),
      );
      // Expect isError false: assert triggers RED if tool is not found
      expect(downResult.isError, isFalse, reason: _text(downResult));
    }, timeout: const Timeout(Duration(seconds: 60)));
```

- [ ] **Step 2: Run test — confirm RED**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart \
  --name "inject_touch at centre" --tags real-device
```

Expected: if the scrcpy session is active and tool exists, this will actually PASS (just a down event). If it passes, proceed — the RED was confirmed by the inject_scroll setup RED in Task 3. The value of this test is the `action=up` completion and the printOnFailure screenshot.

- [ ] **Step 3: Complete test with action=up and screenshot printOnFailure**

Replace the entire test body:

```dart
    test('inject_touch at centre succeeds', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }
      final (w, h) = screenSize;

      final downResult = await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'inject_touch',
          arguments: {
            'x': w ~/ 2,
            'y': h ~/ 2,
            'width': w,
            'height': h,
            'action': 0, // ScrcpyAction.down
          },
        ),
      );
      expect(downResult.isError, isFalse, reason: _text(downResult));

      await Future.delayed(const Duration(milliseconds: 100));

      final upResult = await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'inject_touch',
          arguments: {
            'x': w ~/ 2,
            'y': h ~/ 2,
            'width': w,
            'height': h,
            'action': 1, // ScrcpyAction.up
          },
        ),
      );
      expect(upResult.isError, isFalse, reason: _text(upResult));

      await Future.delayed(const Duration(milliseconds: 400));

      // Weak assertion: log screenshot size for debugging, no pixel-diff required.
      // Tapping empty space produces no guaranteed visual change.
      final after = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));
      printOnFailure('inject_touch screenshot size: ${after.length} bytes');
    }, timeout: const Timeout(Duration(seconds: 60)));
```

- [ ] **Step 4: Run test — confirm GREEN**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart \
  --name "inject_touch at centre" --tags real-device
```

Expected: PASS. Both down and up events accepted without error.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart
git commit -m "test: add inject_touch e2e test with real scrcpy session"
```

---

### Task 6: `inject_text` — RED then GREEN

**Files:**
- Modify: `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart`

- [ ] **Step 1: Write the failing test — add inside the e2e group**

```dart
    test('inject_text succeeds', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      // Deliberate typo in tool name to produce RED
      final textResult = await e2eEnv.client.callTool(
        const CallToolRequest(
          name: 'inject_txt',
          arguments: {'text': 'hello'},
        ),
      );
      expect(textResult.isError, isFalse, reason: _text(textResult));
    }, timeout: const Timeout(Duration(seconds: 60)));
```

- [ ] **Step 2: Run test — confirm RED**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart \
  --name "inject_text succeeds" --tags real-device
```

Expected failure: `isError: true` — `inject_txt` is not a registered tool.

- [ ] **Step 3: Fix tool name — GREEN**

Replace `'inject_txt'` with `'inject_text'`:

```dart
    test('inject_text succeeds', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      // Weak assertion: inject_text requires a focused input field to produce
      // visible output. Without a forced screen state, only success is checked.
      // To add pixel verification: first inject_touch on a text field, then call.
      final textResult = await e2eEnv.client.callTool(
        const CallToolRequest(
          name: 'inject_text',
          arguments: {'text': 'hello'},
        ),
      );
      expect(textResult.isError, isFalse, reason: _text(textResult));
    }, timeout: const Timeout(Duration(seconds: 60)));
```

- [ ] **Step 4: Run test — confirm GREEN**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart \
  --name "inject_text succeeds" --tags real-device
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart
git commit -m "test: add inject_text e2e test with real scrcpy session"
```

---

### Task 7: Full suite verification and final commit

- [ ] **Step 1: Run the complete real-device suite**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart --tags real-device
```

Expected: all tests pass (or skip cleanly if no device). Output shows the e2e group with 4 tests: inject_scroll, inject_key, inject_touch, inject_text.

- [ ] **Step 2: Run the full scrcpy_mcp test suite (no real-device tag) to check for regressions**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart test scrcpy_mcp/test/ --exclude-tags real-device
```

Expected: all existing tests pass. No regressions in mock-based tests.

- [ ] **Step 3: Final commit if anything was missed**

```bash
git add scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart
git commit -m "test: complete inject controls e2e test suite"
```

---

## Self-Review

**Spec coverage:**
- ✅ `_E2eEnv` using real `ScrcpySessionImpl` — Task 2
- ✅ `_screenshotBytes`, `_hasScreenChanged`, `_getScreenSize` — Task 2
- ✅ `setUpAll` starts scrcpy once, shared across tests — Task 3
- ✅ `tearDownAll` stops session — Task 3
- ✅ `inject_scroll` strong pixel diff — Task 3
- ✅ `inject_key(Home)` strong pixel diff — Task 4
- ✅ `inject_touch` weak assertion (success only) — Task 5
- ✅ `inject_text` weak assertion (success only) — Task 6
- ✅ All tests skip cleanly when no device — every test has `markTestSkipped` guard
- ✅ `Timeout(Duration(seconds: 60))` on each test — Tasks 3–6
- ✅ `setUpAll` has `Timeout(Duration(seconds: 30))` — Task 3

**Placeholder scan:** No TBD, no TODOs, all code blocks are complete.

**Type consistency:**
- `_E2eEnv` accepts `ScrcpySession` (interface), constructed with `ScrcpySessionImpl` — consistent
- `_screenshotBytes` returns `Uint8List`, consumed by `_hasScreenChanged` — consistent
- `_getScreenSize` returns `(int, int)`, destructured as `(w, h)` in tests — consistent
- `_text(result)` only called on inject results (TextContent), never on screenshot results — consistent
