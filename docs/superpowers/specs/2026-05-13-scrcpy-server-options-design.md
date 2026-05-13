# ScrcpyServer Configurability — Design Spec

**Date:** 2026-05-13  
**Package:** `packages/scrcpy_client`  
**Status:** Approved

---

## Problem

All video encoding parameters in `ScrcpyServer._runServer` are hardcoded literals:

```dart
'max_size=1024',
'max_fps=60',
'video_bit_rate=6000000',
'video_codec=h264',
```

Callers at the `ScrcpySessionImpl` level have no way to tune these values without forking the class. Additionally, `_parser.close()` is called from two places — the process exit handler and `stop()` — which can cause a double-close.

---

## Goals

- Expose `maxSize`, `maxFps`, `videoBitRate`, and `videoCodec` as configurable video parameters.
- Thread the options through `ScrcpySessionImpl.start()` so app/MCP callers can configure encoding without reaching into `ScrcpyServer` directly.
- Fix the dual `_parser.close()` bug while touching `ScrcpyServer`.
- Keep `controlSink` on the `ScrcpyServer` constructor (used by test infrastructure).
- No other behavior changes.

---

## Non-Goals

- Exposing `scid`, socket name, `audio`, `power_on`, `cleanup`, or other scrcpy server args.
- Adding `copyWith` or builder pattern to the options class.
- Addressing testability or state-machine gaps (separate future concern).

---

## Design

### 1. New file: `lib/src/scrcpy_server_options.dart`

```dart
import 'package:meta/meta.dart';

@immutable
class ScrcpyServerOptions {
  const ScrcpyServerOptions({
    this.maxSize = 1024,
    this.maxFps = 60,
    this.videoBitRate = 6000000,
    this.videoCodec = 'h264',
  });

  /// Maximum dimension of the video stream in pixels (longest side).
  /// Set to 0 for no limit.
  final int maxSize;

  /// Maximum frames per second.
  final int maxFps;

  /// Video bit rate in bits per second.
  final int videoBitRate;

  /// Scrcpy video codec identifier. One of: h264, h265, av1.
  final String videoCodec;
}
```

Defaults match the current hardcoded values so existing callers passing
`const ScrcpyServerOptions()` get identical behaviour.

### 2. `ScrcpyServer` changes (`lib/src/scrcpy_server.dart`)

**Constructor:** add `required ScrcpyServerOptions options` parameter.  
`controlSink` remains unchanged.

```dart
ScrcpyServer({
  required this.adb,
  required this.deviceId,
  required Uint8List serverJarBytes,
  required ScrcpyServerOptions options,   // ← new
  this.port = 27183,
  ScrcpyLogger logger = const NoOpScrcpyLogger(),
  StreamSink<List<int>>? controlSink,
});
```

**`_runServer`:** replace the four hardcoded literals with reads from `options`:

```dart
'max_size=${_options.maxSize}',
'max_fps=${_options.maxFps}',
'video_bit_rate=${_options.videoBitRate}',
'video_codec=${_options.videoCodec}',
```

**Bug fix — dual `_parser.close()`:** The process exit handler currently calls
`_parser.close()`, as does `stop()`. Change the exit handler to only log:

```dart
unawaited(
  _serverProcess!.exitCode.then((code) {
    _log.warn('[ScrcpyServer] server process exited with code $code');
    // _parser.close() removed — stop() is the single owner of cleanup
  }),
);
```

`stop()` remains the sole caller of `_parser.close()`.

### 3. `ScrcpySessionImpl` changes (`lib/src/scrcpy_session_impl.dart`)

Add an optional `options` parameter to `start()`:

```dart
Future<void> start(
  String deviceId, {
  ScrcpyServerOptions options = const ScrcpyServerOptions(),   // ← new
  ScrcpyLogger? logger,
  void Function()? onStarted,
  void Function()? onStopped,
  void Function(String)? onError,
}) async { ... }
```

Forward `options` to the `ScrcpyServer` constructor inside `start()`.

---

## File Changes Summary

| File | Change |
|------|--------|
| `lib/src/scrcpy_server_options.dart` | **New** — `ScrcpyServerOptions` value class |
| `lib/src/scrcpy_server.dart` | Add `options` param, wire into `_runServer`, fix dual-close |
| `lib/src/scrcpy_session_impl.dart` | Add optional `options` to `start()`, forward to server |
| `lib/scrcpy_client.dart` (barrel) | Export `ScrcpyServerOptions` |
| Existing tests | Update `ScrcpyServer(...)` call sites to pass `options: const ScrcpyServerOptions()` |

---

## Testing

No new test files required. Existing unit tests that construct `ScrcpyServer` directly will need `options: const ScrcpyServerOptions()` added — this is a mechanical update. The dual-close fix is validated by the existing parser tests (the parser already guards against double-close internally). No observable behaviour change means no new test cases are needed.
