# scrcpy_client Package Design

**Date:** 2026-05-12
**Status:** Approved

## Goal

Extract all scrcpy-server communication code from `scrcpy_view` into a standalone pure-Dart package `packages/scrcpy_client`, publishable to pub.dev. This eliminates the Flutter transitive dependency in `scrcpy_mcp` and creates a clean, reusable Dart library for any consumer that needs to communicate with a scrcpy-server.

---

## Scope

Approach B: **Protocol layer + ADB orchestration**. The HTTP proxy/WebSocket servers (`ScrcpyProxyServer`, `ScrcpyWebsocketServer`) are rendering concerns tied to specific Flutter video backends and remain in `scrcpy_view`.

Public API exposes two levels:
- **Low-level:** `ScrcpyServer` — socket connection + ADB orchestration
- **High-level:** `ScrcpySession` (abstract) + `ScrcpySessionImpl` (concrete)

---

## Package Structure

```
packages/
  adb_tools/           (unchanged)
  logger_utils/        (unchanged)
  scrcpy_client/       ← NEW, pure Dart, pub.dev
    assets/
      scrcpy-server-v3.3.4   ← moved from scrcpy_view/assets/
    lib/
      scrcpy_client.dart     (public barrel)
      src/
        control_message.dart
        scrcpy_stream_parser.dart
        scrcpy_packet.dart
        scrcpy_adb.dart
        scrcpy_logger.dart
        scrcpy_server.dart       (refactored: no proxy/ws)
        scrcpy_session.dart      (proxyUrl/playerUrl removed)
        scrcpy_session_impl.dart (webPlayerBytes removed)
        android_metastate.dart   (split from scrcpy_metastate.dart)

scrcpy_view/           (Flutter, gains dep on scrcpy_client)
  assets/
    web_player/        (stays here — WebSocket server resource)
  lib/src/
    scrcpy_proxy_server.dart      (unchanged)
    scrcpy_websocket_server.dart  (unchanged)
    mpeg_ts_muxer.dart            (unchanged)
    scrcpy_keycode_flutter.dart   (renamed from scrcpy_keycode.dart)
    scrcpy_metastate_flutter.dart (split from scrcpy_metastate.dart)
    nav_buttons.dart              (unchanged)
    scrcpy_view_controller.dart   (gains proxy/ws management)
    scrcpy_view.dart              (unchanged)

scrcpy_mcp/            (pure Dart, dep: scrcpy_view → scrcpy_client)
scrcpy_app/            (Flutter, dep: scrcpy_view + scrcpy_client)
```

### Dependency graph (single direction, no cycles)

```
scrcpy_app
  ├── scrcpy_view ──► scrcpy_client
  └── scrcpy_client

scrcpy_mcp ──► scrcpy_client   (no Flutter transitive dep)
```

---

## ScrcpyServer Decoupling

### What changes

`ScrcpyServer` currently owns the proxy and WebSocket servers internally. After the refactor it is a pure protocol client:

| Removed from ScrcpyServer | Moved to |
|---------------------------|----------|
| `webPlayerBytes` constructor param | `ScrcpyViewController` |
| `_proxy: ScrcpyProxyServer` field | `ScrcpyViewController` |
| `_wsProxy: ScrcpyWebsocketServer` field | `ScrcpyViewController` |
| `proxyUrl` / `playerUrl` / `proxyReady` getters | `ScrcpyViewController` |
| Proxy/ws startup in `start()` | `ScrcpyViewController.start()` |
| Proxy/ws teardown in `stop()` | `ScrcpyViewController.stop()` |

### ScrcpyServer API after refactor

```dart
class ScrcpyServer {
  ScrcpyServer({
    required ScrcpyAdb adb,
    required String deviceId,
    required Uint8List serverJarBytes,   // webPlayerBytes removed
    int port = 27183,
    ScrcpyLogger logger,
    StreamSink<List<int>>? controlSink,
  });

  Stream<ScrcpyPacket>  get packets;   // unchanged — subscribers attach here
  Stream<ScrcpyMetadata> get metadata; // unchanged

  Future<void> start();   // push JAR → ADB forward → launch process → connect sockets
  Future<void> stop();    // disconnect sockets, kill process, remove forward
  void sendControlMessage(ScrcpyControlMessage message);
}
```

### ScrcpyViewController gains proxy management

After `session.start(deviceId)` completes, `ScrcpyViewController` subscribes to `server.packets` and starts the rendering servers:

```
ScrcpyViewController.start(deviceId)
  1. ScrcpySessionImpl.start(deviceId)          ← scrcpy_client
       └── ScrcpyServer.start()                 ← push JAR, connect sockets
  2. ScrcpyProxyServer.start(server.packets)    ← scrcpy_view
  3. ScrcpyWebsocketServer.start(              ← scrcpy_view
       server.packets, staticPath: webPlayerPath)
  4. Expose proxyUrl / playerUrl via ChangeNotifier
```

---

## ScrcpySession Interface Changes

`proxyUrl` and `playerUrl` are removed from the `ScrcpySession` interface in `scrcpy_client`. These are rendering concerns only relevant to the Flutter widget layer.

```dart
// scrcpy_client — protocol + control contract only
abstract class ScrcpySession {
  bool get isConnected;
  int? get videoWidth;
  int? get videoHeight;
  Future<void> start(String deviceId);
  Future<void> stop();
  void sendControlMessage(ScrcpyControlMessage message);
  void injectText(String text);
}
```

`ScrcpyViewController` (Flutter layer) continues to expose `proxyUrl` / `playerUrl` as its own properties. `scrcpy_mcp` tools only depend on `ScrcpySession` and are unaffected.

---

## File Splitting: keycode & metastate

### scrcpy_keycode.dart → entire file stays in scrcpy_view

The file only contains `androidKeycodeForPhysicalKey(PhysicalKeyboardKey key)` — 100% Flutter-specific. Rename to `scrcpy_keycode_flutter.dart` for clarity. Export only from `scrcpy_view.dart`.

`ScrcpyKeycode` integer constants (`home`, `back`, `appSwitch`) are already in `control_message.dart` and move to `scrcpy_client` with it.

### scrcpy_metastate.dart → split into two files

| Content | Destination |
|---------|-------------|
| `AndroidMetastate` (pure `int` bitmask constants) | `scrcpy_client/src/android_metastate.dart` |
| `ScrcpyMetastate` (`LogicalKeyboardKey` tracker) | `scrcpy_view/src/scrcpy_metastate_flutter.dart` |

---

## Public Barrel: scrcpy_client.dart

```dart
// packages/scrcpy_client/lib/scrcpy_client.dart
export 'src/control_message.dart';       // protocol message serialization
export 'src/scrcpy_stream_parser.dart';  // binary video stream parser
export 'src/scrcpy_packet.dart';         // ScrcpyPacket, ScrcpyMetadata
export 'src/scrcpy_adb.dart';            // ScrcpyAdb abstract interface
export 'src/scrcpy_logger.dart';         // ScrcpyLogger abstract interface
export 'src/scrcpy_server.dart';         // low-level API
export 'src/scrcpy_session.dart';        // high-level abstract interface
export 'src/scrcpy_session_impl.dart';   // high-level concrete implementation
export 'src/android_metastate.dart';     // AndroidMetastate bitmask constants
```

---

## pubspec Changes

### packages/scrcpy_client/pubspec.yaml (new)

```yaml
name: scrcpy_client
description: Pure-Dart client for the scrcpy Android screen-mirroring protocol.
  Handles ADB orchestration, socket communication, video stream parsing,
  and control message injection.
version: 0.1.0
homepage: https://github.com/sunbird89629/autoglm_scrcpy_flutter

environment:
  sdk: ^3.5.0

dependencies:
  path: ^1.9.0

flutter:
  assets:
    - assets/scrcpy-server-v3.3.4
```

### scrcpy_view/pubspec.yaml

```yaml
dependencies:
  scrcpy_client:
    path: ../packages/scrcpy_client
  # existing deps unchanged
```

### scrcpy_mcp/pubspec.yaml

```yaml
dependencies:
  scrcpy_client:           # replaces scrcpy_view
    path: ../packages/scrcpy_client
  adb_tools:
    path: ../packages/adb_tools
  logger_utils:
    path: ../packages/logger_utils
  mcp_dart: ^2.1.1
```

### melos.yaml

Add `packages/scrcpy_client` to the workspace `packages:` list.

---

## Asset Migration

| Asset | From | To | Reason |
|-------|------|----|--------|
| `scrcpy-server-v3.3.4` | `scrcpy_view/assets/` | `scrcpy_client/assets/` | Core protocol binary, belongs with the client |
| `web_player/` | `scrcpy_view/assets/` | stays | WebSocket server resource, rendering concern |

`ScrcpySessionImpl.create()` resolves the JAR via `Isolate.resolvePackageUri('package:scrcpy_client/...')` after the move.

---

## Testing Strategy

- All existing `scrcpy_view/test/control_message_test.dart` and `control_send_test.dart` tests move to `scrcpy_client/test/` with import paths updated.
- `scrcpy_client` tests have no Flutter dep — run with `dart test`.
- `scrcpy_view` tests retain widget and proxy server tests — run with `flutter test`.
- `scrcpy_mcp` real-device tests continue to use `ScrcpySession` from `scrcpy_client`.

---

## Migration Steps (implementation order)

1. Create `packages/scrcpy_client/` with pubspec and empty barrel
2. Move pure-Dart files into `scrcpy_client/src/`
3. Split `scrcpy_metastate.dart` → `android_metastate.dart` + `scrcpy_metastate_flutter.dart`
4. Rename `scrcpy_keycode.dart` → `scrcpy_keycode_flutter.dart` in `scrcpy_view`
5. Move JAR asset to `scrcpy_client/assets/`
6. Refactor `ScrcpyServer`: remove proxy/ws construction and startup
7. Refactor `ScrcpySession`: remove `proxyUrl`/`playerUrl`
8. Refactor `ScrcpySessionImpl`: remove `webPlayerBytes`, update asset resolution
9. Refactor `ScrcpyViewController`: add proxy/ws lifecycle management
10. Update `scrcpy_view/pubspec.yaml` to depend on `scrcpy_client`
11. Update `scrcpy_mcp/pubspec.yaml` to depend on `scrcpy_client`
12. Update all import paths in `scrcpy_mcp/` and `scrcpy_view/`
13. Move tests to `scrcpy_client/test/`
14. `melos bootstrap` + `dart analyze` + `flutter analyze` + full test run
