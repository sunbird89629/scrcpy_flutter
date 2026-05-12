# Inject Controls E2E Test Design

**Date:** 2026-05-08  
**Scope:** Real-device effect verification for `inject_scroll`, `inject_touch`, `inject_key`, `inject_text` MCP tools  
**File:** `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart` (new group appended)

---

## Goal

Verify that inject control commands actually affect device UI, not just that the MCP layer accepts them. The existing mock-session tests already cover protocol correctness; this design adds a new test group that exercises the full production path: scrcpy control socket → device → visible screen change.

---

## Architecture

```
ScrcpySessionImpl (real JAR + control socket)
       │  start(deviceId)
       ▼
ScrcpyMcpServer(session: realSession, adb: realAdb)
       │  IOStreamTransport (in-memory)
       ▼
McpClient
       │
  tests: take_screenshot → inject_* → take_screenshot → pixel diff
```

**Key properties:**
- `ScrcpySessionImpl.create(adb: realAdb)` loads the scrcpy JAR from package assets and constructs the session. No external asset path needed.
- All test interactions go through the MCP client (tool calls), exercising the same code path as production.
- Screenshots are taken via the `take_screenshot` MCP tool, which calls `ScrcpyMcpAdb.takeScreenshot` (ADB screencap). This is independent of the scrcpy video stream and always reflects the current device screen.

---

## Test Environment

### New `_E2eEnv` class

A separate env class accepts any `ScrcpySession` (including `ScrcpySessionImpl`). The existing `_Env` and `_MockScrcpySession` are unchanged to avoid touching passing tests.

```dart
class _E2eEnv {
  _E2eEnv({required ScrcpyMcpAdb adb, required ScrcpySession session})
      : _session = session {
    server = ScrcpyMcpServer(session: session, adb: adb);
  }

  final ScrcpySession _session;
  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async { /* same IOStreamTransport wiring as _Env */ }
}
```

### Lifecycle

| Phase | Action |
|-------|--------|
| `setUpAll` | `AdbClientImpl()` → `ScrcpyMcpAdb` → `ScrcpySessionImpl.create()` → `_E2eEnv.connect()` → `start_mirroring` |
| Each test | Take before screenshot, inject command, wait, take after screenshot, assert |
| `tearDownAll` | `stop_mirroring` → session released |

scrcpy startup (JAR push, port forwarding, socket handshake) takes 3–10 s; running it once in `setUpAll` amortises this cost across all four inject tests.

---

## Pixel Diff Helper

Android's `adb screencap -p` produces deterministic PNG output: identical screen content produces byte-identical files. Comparing raw PNG bytes is therefore a valid proxy for "did anything on screen change."

```dart
Uint8List _screenshotBytes(CallToolResult r) =>
    base64Decode((r.content.first as ImageContent).data);

bool _hasScreenChanged(Uint8List before, Uint8List after, {int threshold = 100}) {
  if (before.length != after.length) return true;
  var diff = 0;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i] && ++diff > threshold) return true;
  }
  return false;
}
```

`threshold = 100` is deliberately conservative: a single changed pixel in a PNG typically cascades into hundreds of different compressed bytes, so this threshold avoids false positives from unrelated system UI changes (clock tick, notification badge) while catching genuine content shifts.

No new dependencies — `dart:convert` (`base64Decode`) is already imported.

---

## Device Resolution

Scroll and touch events require screen dimensions. Resolved in `setUpAll`:

```dart
Future<(int w, int h)> _getScreenSize(ScrcpyMcpAdb adb, String deviceId) async {
  final result = await adb.shell(['wm', 'size'], deviceId: deviceId);
  final m = RegExp(r'(\d+)x(\d+)').firstMatch(result.stdout as String);
  if (m == null) return (1080, 1920); // safe fallback
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}
```

---

## Per-Command Test Logic

### inject_scroll
- **Action:** scroll down at screen center (`x = w/2, y = h/2, vScroll = -3`)
- **Wait:** 800 ms (scroll animation)
- **Assertion:** strong — `_hasScreenChanged` must be `true`
- **Rationale:** any scrollable surface (home screen icon grid, recents, list app) will shift content

### inject_key (Home = 3)
- **Action:** send keycode 3 (Home)
- **Wait:** 500 ms (navigation transition)
- **Assertion:** strong — `_hasScreenChanged` must be `true`
- **Rationale:** Home key always triggers a navigation event or launcher animation

### inject_touch (centre tap)
- **Action:** `action=down` then `action=up` at screen centre
- **Wait:** 500 ms
- **Assertion:** weak — only `isError: false` required; pixel diff logged via `printOnFailure` but does not fail the test
- **Rationale:** tapping empty space produces no visible change; without forced screen state we cannot guarantee a tap target exists

### inject_text
- **Action:** send `"hello"` via inject_text
- **Wait:** 300 ms
- **Assertion:** weak — only `isError: false` required
- **Rationale:** text injection requires a focused input field; without forced screen state visual verification is unreliable. To upgrade this to a strong assertion in future, first tap a text field with inject_touch, then inject_text.

---

## Timing Summary

| Command | Wait | Assertion |
|---------|------|-----------|
| inject_scroll | 800 ms | Strong (pixel diff) |
| inject_key | 500 ms | Strong (pixel diff) |
| inject_touch | 500 ms | Weak (success only) |
| inject_text | 300 ms | Weak (success only) |

Each test has `Timeout(Duration(seconds: 60))`. The group's `setUpAll` has `Timeout(Duration(seconds: 30))` to account for scrcpy startup.

---

## File Structure

All new code appended to `scrcpy_mcp/test/scrcpy_mcp_real_device_test.dart`:

```
// existing content unchanged
// ...

// --- new additions ---
class _E2eEnv { ... }

Uint8List _screenshotBytes(CallToolResult r) { ... }
bool _hasScreenChanged(Uint8List, Uint8List, {int threshold}) { ... }
Future<(int, int)> _getScreenSize(ScrcpyMcpAdb, String) { ... }

group('real device — inject controls (e2e)', () {
  setUpAll(...)    // start scrcpy once
  tearDownAll(...) // stop session
  test('inject_scroll changes screen content', ...)
  test('inject_key Home navigates to launcher', ...)
  test('inject_touch at centre succeeds', ...)
  test('inject_text succeeds', ...)
});
```

Tags: inherited from `@Tags(['real-device'])` at file top.

---

## Out of Scope

- Strong pixel-diff assertion for inject_text (requires pre-focused input field)
- Strong pixel-diff assertion for inject_touch (requires known tap target)
- Performance benchmarking of control socket latency
- Testing inject_scroll with specific scrollable app state
