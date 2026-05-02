# MCP HTTP Server Integration Design

**Date:** 2026-05-02  
**Status:** Approved  
**Scope:** `scrcpy_mcp` package + `scrcpy_app`

## Overview

Add an HTTP-based MCP server to `scrcpy_app`. Users click a button to start a local StreamableHTTP MCP server; AI agents configured with the server URL can then control the Android device (touch, key, text, scroll, screenshot) and share the same mirroring session visible in the UI.

## Decisions

| Question | Decision |
|---|---|
| MCP library | Migrate from `dart_mcp ^0.4.1` to `mcp_dart ^2.1.1` |
| Transport | StreamableHTTP (modern MCP spec 2025-11-25) |
| Session sharing | Option C — AI and UI share one `ScrcpyViewController` |
| Port | User-configurable, default 7070 |
| Screenshot tool | Yes, via `adb exec-out screencap -p` |

## Architecture

```
scrcpy_app
├── AppController
│   ├── ScrcpyViewController  ← shared session (UI + MCP)
│   └── McpServerController   ← new, manages HTTP server lifecycle
│
└── UI (HomePage)
    ├── Expanded: DeviceListWidget / ScrcpyView  ← existing
    └── McpServerPanel (new Widget, always visible at bottom)

scrcpy_mcp (refactored)
├── ScrcpyMcpServer  ← migrated to mcp_dart
└── McpHttpServer    ← new, wraps server with StreamableHttpServerTransport
```

## Component Details

### `ScrcpyMcpServer` (refactored)

Migrated from `dart_mcp` to `mcp_dart`. Constructor changes:

```dart
ScrcpyMcpServer({
  required ScrcpyViewController viewController,
  required ScrcpyAdb adb,
})
```

No longer manages its own `ScrcpyServer`. All session operations go through `viewController`.

**Tool → implementation mapping:**

| Tool | Implementation |
|---|---|
| `list_devices` | `adb.getDevices()` |
| `start_mirroring` | `viewController.start(deviceId)` |
| `stop_mirroring` | `viewController.stop()` |
| `inject_key` | `viewController.injectKey(keycode)` |
| `inject_touch` | `viewController.sendControlMessage(ScrcpyInjectTouchMessage(...))` |
| `inject_text` | `viewController.injectText(text)` |
| `inject_scroll` | `viewController.sendControlMessage(ScrcpyInjectScrollMessage(...))` |
| `take_screenshot` | `adb.takeScreenshot(deviceId)` → base64 PNG in `EmbeddedResource` |

### `McpHttpServer` (new, in `scrcpy_mcp`)

```dart
class McpHttpServer {
  Future<void> start({
    required int port,
    required ScrcpyViewController viewController,
    required ScrcpyAdb adb,
  });
  Future<void> stop();
  String? get serverUrl;  // "http://localhost:$port/mcp" when running
}
```

Internally creates `ScrcpyMcpServer` and connects it to a `StreamableHttpServerTransport`.

### `ScrcpyAdb` interface change

Add to interface:

```dart
Future<Uint8List> takeScreenshot(String deviceId);
```

Implement in both `ScrcpyMcpAdb` (scrcpy_mcp) and `ScrcpyAppAdb` (scrcpy_app) using `adb exec-out screencap -p` with binary stdout.

### `McpServerController` (new, in `scrcpy_app`)

```dart
class McpServerController extends ChangeNotifier {
  McpServerController({
    required ScrcpyViewController viewController,
    required ScrcpyAdb adb,
  });

  int port = 7070;
  bool get isRunning;
  String? get serverUrl;
  String? get errorMessage;

  Future<void> start();
  Future<void> stop();
}
```

`ScrcpyViewController` and `ScrcpyAdb` are injected at construction time by `AppController`, which owns both. On `start()` failure (e.g. port in use), sets `errorMessage` and notifies listeners.

`AppController` creates `McpServerController` alongside `ScrcpyViewController`:

```dart
class AppController extends ChangeNotifier {
  final scrcpyViewController = ScrcpyViewController(adb: ScrcpyAppAdb(AdbClient()));
  late final mcpServerController = McpServerController(
    viewController: scrcpyViewController,
    adb: ScrcpyAppAdb(AdbClient()),
  );
}
```

### `McpServerPanel` (new Widget, in `scrcpy_app`)

Always rendered at the bottom of `HomePage` inside a `Column`. Two visual states:

**Idle:**
```
MCP Server    Port: [7070]    [Start]
```

**Running:**
```
MCP ● Running   http://localhost:7070/mcp   [Copy]   [Stop]
```

**Error:**
```
MCP Server    Port: [7070]    [Start]
⚠ Port 7070 already in use
```

### `HomePage` changes

`Scaffold` body becomes a `Column`:
- `Expanded`: existing device list / ScrcpyView
- `McpServerPanel`: fixed at bottom, always visible

## `scrcpy_mcp` Dependency Changes

```yaml
# Remove:
dart_mcp: ^0.4.1
stream_channel: ^2.1.0

# Add:
mcp_dart: ^2.1.1
```

## AI Agent Configuration (end result)

```json
{
  "mcpServers": {
    "scrcpy": {
      "type": "streamable_http",
      "url": "http://localhost:7070/mcp"
    }
  }
}
```

## Out of Scope

- Authentication / access control (localhost-only, trusted environment)
- Multiple simultaneous MCP clients
- Persistent port setting across app restarts
- Stdio transport changes (existing `bin/scrcpy_mcp.dart` kept as-is)
