# scrcpy_view

Embeddable Flutter widget for Android screen mirroring via the [Scrcpy](https://github.com/Genymobile/scrcpy) protocol.

## Features

- **Zero-config mirroring** — push the scrcpy server JAR to the device, set up ADB forwarding, and start streaming
- **H.264 live video** — binary protocol parser with SPS/PPS injection for late-joiner support
- **Touch & control injection** — tap, swipe, scroll, key events, and text input via the scrcpy v3 binary control protocol
- **Multiple backends** — HTTP proxy (MPEG-TS for media_kit) and WebSocket server with bundled web player
- **Pluggable abstractions** — `ScrcpyAdb` and `ScrcpyLogger` interfaces; consumers provide their own implementations

## Quick Start

```dart
import 'package:scrcpy_view/scrcpy_view.dart';

// 1. Create a controller with your ADB and logger implementations
final controller = ScrcpyViewController(
  adb: myScrcpyAdb,
  logger: myScrcpyLogger,
);

// 2. Start mirroring a device
await controller.start('device-serial-id');

// 3. Embed the view
ScrcpyView(controller: controller)

// 4. Inject input
controller.sendControlMessage(
  ControlMessage.tap(x: 500, y: 500),
);
```

## Architecture

```
ScrcpyView (widget)
  └─ ScrcpyViewController
       └─ ScrcpyServer (lifecycle orchestration)
            ├─ ScrcpyStreamParser (H.264 binary protocol)
            ├─ ScrcpyProxyServer (HTTP → MPEG-TS)
            ├─ ScrcpyWebsocketServer (WebSocket + web player)
            └─ ControlMessage (input injection)
```

### Key classes

| Class | Purpose |
|-------|---------|
| `ScrcpyView` | Stateless widget that renders the video stream |
| `ScrcpyViewController` | Manages server lifecycle, exposes input injection |
| `ScrcpyServer` | Orchestrates: push JAR → ADB forward → launch server → bridge sockets |
| `ScrcpyStreamParser` | Parses 64-byte device name + 12-byte codec header, then PTS+length frames |
| `ScrcpyProxyServer` | HTTP server remuxing H.264 into MPEG-TS for media_kit |
| `ScrcpyWebsocketServer` | WebSocket + static HTTP server for web player |
| `ControlMessage` | Scrcpy v3 control protocol: keycode, text, touch, scroll |
| `ScrcpyAdb` | Abstract ADB interface — consumers provide implementations |
| `ScrcpyLogger` | Abstract logging interface |

## Assets

Bundled in `assets/`:

- `scrcpy-server-v3.3.4` — scrcpy server JAR pushed to the Android device at runtime
- `web_player/` — HTML/JS video player served via WebSocket

## Dependencies

- `flutter_inappwebview` — WebView for video rendering
- `shelf` / `shelf_static` / `shelf_web_socket` — HTTP and WebSocket servers
- `path_provider` — temp directory for extracted assets

## Related packages

- [scrcpy_app](../scrcpy_app/) — Standalone desktop client using this package
- [scrcpy_mcp](../scrcpy_mcp/) — MCP server wrapping scrcpy operations
