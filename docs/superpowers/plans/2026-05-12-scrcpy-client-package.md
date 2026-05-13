# scrcpy_client Package Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract all scrcpy-server communication code from `scrcpy_view` into a new standalone pure-Dart package `packages/scrcpy_client`, publishable to pub.dev, eliminating the Flutter transitive dependency from `scrcpy_mcp`.

**Architecture:** Create `packages/scrcpy_client` (pure Dart) containing the protocol layer + ADB orchestration. `scrcpy_view` gains a dependency on `scrcpy_client` and retains only Flutter widgets and HTTP/WebSocket proxy servers. `scrcpy_mcp` switches its dependency from `scrcpy_view` to `scrcpy_client`.

**Tech Stack:** Dart 3.5+, `path` package, `dart test` (scrcpy_client), `flutter test` (scrcpy_view), Melos workspace.

**Spec:** `docs/superpowers/specs/2026-05-12-scrcpy-client-package-design.md`

---

## Task 1: Create scrcpy_client package scaffold

**Files:**
- Create: `packages/scrcpy_client/pubspec.yaml`
- Create: `packages/scrcpy_client/lib/scrcpy_client.dart`
- Create: `packages/scrcpy_client/test/.gitkeep`
- Modify: `pubspec.yaml` (root workspace)

- [ ] **Step 1: Create package directories**

```bash
mkdir -p packages/scrcpy_client/lib/src
mkdir -p packages/scrcpy_client/assets
mkdir -p packages/scrcpy_client/test
```

- [ ] **Step 2: Write pubspec.yaml**

Create `packages/scrcpy_client/pubspec.yaml`:

```yaml
name: scrcpy_client
description: >-
  Pure-Dart client for the scrcpy Android screen-mirroring protocol.
  Handles ADB orchestration, socket communication, video stream parsing,
  and control message injection.
version: 0.1.0
homepage: https://github.com/sunbird89629/autoglm_scrcpy_flutter

environment:
  sdk: ^3.5.0

resolution: workspace

dependencies:
  path: ^1.9.0

dev_dependencies:
  test: any
```

- [ ] **Step 3: Write empty barrel**

Create `packages/scrcpy_client/lib/scrcpy_client.dart`:

```dart
library;
```

- [ ] **Step 4: Add scrcpy_client to workspace**

In root `pubspec.yaml`, add `packages/scrcpy_client` to the `workspace:` list (keep alphabetical order within packages/):

```yaml
workspace:
  - packages/adb_tools
  - packages/logger_utils
  - packages/scrcpy_client    # ← add this line
  - scrcpy_app
  - scrcpy_flutter
  - scrcpy_mcp
  - scrcpy_view
```

- [ ] **Step 5: Bootstrap**

```bash
cd /Users/hao/ai/mobile/asf_dev && melos bootstrap
```

Expected: resolves without errors, `packages/scrcpy_client` listed in output.

- [ ] **Step 6: Commit**

```bash
git add packages/scrcpy_client/ pubspec.yaml
git commit -m "chore: create scrcpy_client package scaffold"
```

---

## Task 2: Copy pure protocol files into scrcpy_client/src/

These five files have no dependency on proxy/ws servers. Copy them and update their internal imports from `package:scrcpy_view/src/` to `package:scrcpy_client/src/`.

**Files:**
- Create: `packages/scrcpy_client/lib/src/scrcpy_packet.dart`
- Create: `packages/scrcpy_client/lib/src/scrcpy_adb.dart`
- Create: `packages/scrcpy_client/lib/src/scrcpy_logger.dart`
- Create: `packages/scrcpy_client/lib/src/control_message.dart`
- Create: `packages/scrcpy_client/lib/src/scrcpy_stream_parser.dart`

- [ ] **Step 1: Copy scrcpy_packet.dart** (no import changes needed — only imports `dart:typed_data`)

```bash
cp scrcpy_view/lib/src/scrcpy_packet.dart packages/scrcpy_client/lib/src/scrcpy_packet.dart
```

- [ ] **Step 2: Copy scrcpy_adb.dart** (no import changes needed — only imports `dart:io` and `dart:typed_data`)

```bash
cp scrcpy_view/lib/src/scrcpy_adb.dart packages/scrcpy_client/lib/src/scrcpy_adb.dart
```

- [ ] **Step 3: Copy scrcpy_logger.dart** (no import changes needed — no external imports)

```bash
cp scrcpy_view/lib/src/scrcpy_logger.dart packages/scrcpy_client/lib/src/scrcpy_logger.dart
```

- [ ] **Step 4: Copy control_message.dart** (no import changes — only imports `dart:convert` and `dart:typed_data`)

```bash
cp scrcpy_view/lib/src/control_message.dart packages/scrcpy_client/lib/src/control_message.dart
```

- [ ] **Step 5: Copy scrcpy_stream_parser.dart and update its imports**

```bash
cp scrcpy_view/lib/src/scrcpy_stream_parser.dart packages/scrcpy_client/lib/src/scrcpy_stream_parser.dart
```

Edit `packages/scrcpy_client/lib/src/scrcpy_stream_parser.dart` — replace the two `scrcpy_view` imports:

```dart
// Before:
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_packet.dart';

// After:
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_packet.dart';
```

- [ ] **Step 6: Verify**

```bash
cd /Users/hao/ai/mobile/asf_dev && dart analyze packages/scrcpy_client/lib/src/
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add packages/scrcpy_client/lib/src/
git commit -m "feat(scrcpy_client): copy protocol files from scrcpy_view"
```

---

## Task 3: Create android_metastate.dart and rename scrcpy_keycode.dart

**Files:**
- Create: `packages/scrcpy_client/lib/src/android_metastate.dart`
- Create: `scrcpy_view/lib/src/scrcpy_metastate_flutter.dart`
- Rename: `scrcpy_view/lib/src/scrcpy_keycode.dart` → `scrcpy_view/lib/src/scrcpy_keycode_flutter.dart`
- Delete: `scrcpy_view/lib/src/scrcpy_metastate.dart` (after split)

- [ ] **Step 1: Create android_metastate.dart in scrcpy_client**

Create `packages/scrcpy_client/lib/src/android_metastate.dart`:

```dart
/// Android `KeyEvent` metastate bitmask constants.
class AndroidMetastate {
  static const int shiftOn = 0x00000001;
  static const int altOn = 0x00000002;
  static const int ctrlOn = 0x00001000;
  static const int metaOn = 0x00010000;
}
```

- [ ] **Step 2: Create scrcpy_metastate_flutter.dart in scrcpy_view**

Create `scrcpy_view/lib/src/scrcpy_metastate_flutter.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:scrcpy_client/src/android_metastate.dart';

/// Tracks modifier key state and produces the Android metastate bitmask
/// to attach to key injection messages.
class ScrcpyMetastate {
  bool _shift = false;
  bool _alt = false;
  bool _ctrl = false;
  bool _meta = false;

  /// Current metastate bitmask for inclusion in key injection messages.
  int get bitmask {
    int m = 0;
    if (_shift) m |= AndroidMetastate.shiftOn;
    if (_alt) m |= AndroidMetastate.altOn;
    if (_ctrl) m |= AndroidMetastate.ctrlOn;
    if (_meta) m |= AndroidMetastate.metaOn;
    return m;
  }

  /// Updates internal modifier state based on [logicalKey].
  ///
  /// Returns `true` if the key is a modifier (Shift/Alt/Ctrl/Meta),
  /// `false` otherwise.
  bool handleKey(LogicalKeyboardKey logicalKey, {required bool isDown}) {
    if (_isShift(logicalKey)) {
      _shift = isDown;
      return true;
    }
    if (_isAlt(logicalKey)) {
      _alt = isDown;
      return true;
    }
    if (_isCtrl(logicalKey)) {
      _ctrl = isDown;
      return true;
    }
    if (_isMeta(logicalKey)) {
      _meta = isDown;
      return true;
    }
    return false;
  }

  static bool _isShift(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.shift ||
      k == LogicalKeyboardKey.shiftLeft ||
      k == LogicalKeyboardKey.shiftRight;

  static bool _isAlt(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.alt ||
      k == LogicalKeyboardKey.altLeft ||
      k == LogicalKeyboardKey.altRight;

  static bool _isCtrl(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.control ||
      k == LogicalKeyboardKey.controlLeft ||
      k == LogicalKeyboardKey.controlRight;

  static bool _isMeta(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.meta ||
      k == LogicalKeyboardKey.metaLeft ||
      k == LogicalKeyboardKey.metaRight;
}
```

- [ ] **Step 3: Rename scrcpy_keycode.dart → scrcpy_keycode_flutter.dart**

```bash
git mv scrcpy_view/lib/src/scrcpy_keycode.dart scrcpy_view/lib/src/scrcpy_keycode_flutter.dart
```

- [ ] **Step 4: Delete the original scrcpy_metastate.dart**

```bash
git rm scrcpy_view/lib/src/scrcpy_metastate.dart
```

- [ ] **Step 5: Verify**

```bash
cd /Users/hao/ai/mobile/asf_dev && dart analyze packages/scrcpy_client/lib/src/android_metastate.dart
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add packages/scrcpy_client/lib/src/android_metastate.dart \
        scrcpy_view/lib/src/scrcpy_metastate_flutter.dart \
        scrcpy_view/lib/src/scrcpy_keycode_flutter.dart
git commit -m "refactor: split metastate, rename keycode for scrcpy_client extraction"
```

---

## Task 4: Copy and refactor ScrcpyServer into scrcpy_client

Remove `webPlayerBytes`, `ScrcpyProxyServer`, `ScrcpyWebsocketServer`, `proxyUrl`, `playerUrl`, `proxyReady` from `ScrcpyServer`. The server becomes a pure protocol client.

**Files:**
- Create: `packages/scrcpy_client/lib/src/scrcpy_server.dart`

- [ ] **Step 1: Create the refactored scrcpy_server.dart**

Create `packages/scrcpy_client/lib/src/scrcpy_server.dart` with the full contents below. Key changes from the original: removed `webPlayerBytes`, `_proxy`, `_wsProxy`, `proxyUrl`, `playerUrl`, `proxyReady`, `_prepareWebPlayer()`, and the proxy startup/teardown calls.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_adb.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_packet.dart';
import 'package:scrcpy_client/src/scrcpy_stream_parser.dart';

/// Manages a scrcpy server instance on a device.
class ScrcpyServer {
  /// The scrcpy server version bundled with this package.
  static const serverVersion = '3.3.4';

  ScrcpyServer({
    required this.adb,
    required this.deviceId,
    required Uint8List serverJarBytes,
    this.port = 27183,
    ScrcpyLogger logger = const NoOpScrcpyLogger(),
    StreamSink<List<int>>? controlSink,
  })  : _serverJarBytes = serverJarBytes,
        _log = logger,
        _controlSink = controlSink,
        _parser = ScrcpyStreamParser(logger: logger);

  final ScrcpyAdb adb;
  final String deviceId;
  final int port;

  final Uint8List _serverJarBytes;
  final ScrcpyLogger _log;
  final ScrcpyStreamParser _parser;
  bool _isStarting = false;

  Process? _serverProcess;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final StreamSink<List<int>>? _controlSink;
  Socket? _videoSocket;
  Socket? _controlSocket;
  StreamSubscription<Uint8List>? _videoSubscription;

  int? _actualPort;

  /// Stream of parsed scrcpy packets (video frames).
  Stream<ScrcpyPacket> get packets => _parser.packets;

  /// Stream of scrcpy metadata (device name, codec info).
  Stream<ScrcpyMetadata> get metadata => _parser.metadata;

  /// Last parsed metadata, or `null` if the header has not arrived yet.
  ScrcpyMetadata? get currentMetadata => _parser.currentMetadata;

  /// Starts the scrcpy server: pushes JAR, sets up ADB forward,
  /// launches the on-device process, and connects video + control sockets.
  Future<void> start() async {
    if (_isStarting) return;
    _isStarting = true;

    try {
      _log.info('[ScrcpyServer] Starting for device: $deviceId');
      await _pushServer();

      const scid = '12345678';
      const socketName = 'scrcpy_12345678';

      await _setupForwardWithRetry(socketName);
      await _runServer(scid);
      await _connectAll();
    } finally {
      _isStarting = false;
    }
  }

  /// Sends a control message to the device.
  void sendControlMessage(ScrcpyControlMessage message) {
    final sink = _controlSink ?? _controlSocket;
    if (sink == null) {
      _log.warn('[ScrcpyServer] Cannot send control message: Not connected');
      return;
    }
    sink.add(message.toBinary());
  }

  Future<void> _pushServer() async {
    const version = serverVersion;
    const remotePath = '/data/local/tmp/scrcpy-server-v$version.jar';

    try {
      _log.debug('[ScrcpyServer] Writing server JAR to temp file');
      final tempDir = Directory.systemTemp;
      final localTempFile = File(
        p.join(tempDir.path, 'scrcpy-server-v$version.jar'),
      );
      await localTempFile.writeAsBytes(_serverJarBytes, flush: true);
      _log.debug('[ScrcpyServer] Pushing server to device: $remotePath');
      await adb.push(localTempFile.path, remotePath, deviceId: deviceId);
      await localTempFile.delete();
    } on Exception catch (e, st) {
      _log.error('[ScrcpyServer] Failed to prepare server on device', e, st);
      rethrow;
    }
  }

  Future<void> _setupForwardWithRetry(String socketName) async {
    const maxRetries = 10;
    var currentPort = port;

    for (var i = 0; i < maxRetries; i++) {
      try {
        _log.debug(
          '[ScrcpyServer] Setting up forward: tcp:$currentPort'
          ' -> localabstract:$socketName',
        );
        try {
          await adb.forwardRemove('tcp:$currentPort', deviceId: deviceId);
        } catch (_) {}
        await adb.forward(
          'tcp:$currentPort',
          'localabstract:$socketName',
          deviceId: deviceId,
        );
        _actualPort = currentPort;
        return;
      } on Exception catch (e) {
        _log.warn(
          '[ScrcpyServer] Failed to forward on port $currentPort, retrying...',
          e,
        );
        currentPort++;
      }
    }
    throw Exception(
      'Failed to setup port forwarding after $maxRetries attempts',
    );
  }

  Future<void> _runServer(String scidHex) async {
    const version = serverVersion;
    const remotePath = '/data/local/tmp/scrcpy-server-v$version.jar';

    try {
      await adb.shell(['pkill', '-f', 'scrcpy-server-v'], deviceId: deviceId);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final args = [
      if (deviceId.isNotEmpty) ...['-s', deviceId],
      'shell',
      'CLASSPATH=$remotePath',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      version,
      'scid=$scidHex',
      'tunnel_forward=true',
      'video_codec=h264',
      'audio=false',
      'control=true',
      'cleanup=true',
      'max_size=1024',
      'max_fps=60',
      'video_bit_rate=6000000',
      'list_encoders=false',
      'list_displays=false',
      'send_dummy_byte=true',
      'video_codec_options=i-frame-interval=1,latency=1',
      'power_on=true',
    ];

    _log.debug('[ScrcpyServer] Executing: adb ${args.join(' ')}');
    _serverProcess = await Process.start(adb.adbPath, args);

    _stdoutSubscription = _serverProcess!.stdout
        .transform(utf8.decoder)
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) _log.debug('[ScrcpyServer:stdout] $trimmed');
    });

    _stderrSubscription = _serverProcess!.stderr
        .transform(utf8.decoder)
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      if (trimmed.contains('ERROR') || trimmed.contains('Exception')) {
        _log.error('[ScrcpyServer:stderr] $trimmed');
      } else {
        _log.warn('[ScrcpyServer:stderr] $trimmed');
      }
    });

    unawaited(
      _serverProcess!.exitCode.then((code) {
        _log.warn('[ScrcpyServer] server process exited with code $code');
        _parser.close();
      }),
    );

    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> _connectAll() async {
    _videoSocket = await _connectSocket('Video');

    var isFirstByteHandled = false;
    _videoSubscription = _videoSocket!.listen(
      (data) {
        if (!isFirstByteHandled) {
          isFirstByteHandled = true;
          if (data.isNotEmpty && data[0] == 0) {
            if (data.length > 1) _parser.feed(Uint8List.sublistView(data, 1));
            return;
          }
        }
        _parser.feed(data);
      },
      onDone: () => _log.warn('[ScrcpyServer] Video socket closed'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    _controlSocket = await _connectSocket('Control');
    // Without TCP_NODELAY, sub-MTU control messages (DOWN/MOVE/UP) are batched,
    // collapsing gesture timing and breaking velocity-sensitive input handling.
    _controlSocket!.setOption(SocketOption.tcpNoDelay, true);
    _controlSocket!.listen(
      (data) => _log.debug('[ScrcpyServer] Control data: ${data.length} bytes'),
      onDone: () => _log.warn('[ScrcpyServer] Control socket closed'),
    );

    _log.info('[ScrcpyServer] All sockets connected with SCID 0.');
  }

  Future<Socket> _connectSocket(String name) async {
    const maxAttempts = 30;
    const retryDelay = Duration(milliseconds: 500);
    final connectPort = _actualPort ?? port;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _log.debug(
          '[ScrcpyServer] [$name] Connecting to localhost:$connectPort'
          ' (attempt $attempt)',
        );
        return await Socket.connect('localhost', connectPort);
      } on Exception catch (e) {
        if (attempt >= maxAttempts) rethrow;
        _log.debug('[ScrcpyServer] [$name] attempt $attempt failed: $e');
        await Future<void>.delayed(retryDelay);
      }
    }
    throw Exception('Failed to connect to $name socket');
  }

  /// Stops the scrcpy server and releases all resources.
  Future<void> stop() async {
    _log.info('[ScrcpyServer] Stopping for device: $deviceId');

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    await _videoSubscription?.cancel();
    _videoSubscription = null;
    await _videoSocket?.close();
    _videoSocket = null;
    await _controlSocket?.close();
    _controlSocket = null;

    _serverProcess?.kill();
    _serverProcess = null;

    final cleanupPort = _actualPort ?? port;
    try {
      await adb.forwardRemove('tcp:$cleanupPort', deviceId: deviceId);
    } catch (_) {}

    _parser.close();
  }
}
```

- [ ] **Step 2: Verify**

```bash
cd /Users/hao/ai/mobile/asf_dev && dart analyze packages/scrcpy_client/lib/src/scrcpy_server.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add packages/scrcpy_client/lib/src/scrcpy_server.dart
git commit -m "feat(scrcpy_client): add refactored ScrcpyServer without proxy/ws deps"
```

---

## Task 5: Copy and refactor ScrcpySession + ScrcpySessionImpl into scrcpy_client

Remove `proxyUrl`/`playerUrl` from the `ScrcpySession` interface. Remove `webPlayerBytes` from `ScrcpySessionImpl`. Update asset resolution to `package:scrcpy_client`.

**Files:**
- Create: `packages/scrcpy_client/lib/src/scrcpy_session.dart`
- Create: `packages/scrcpy_client/lib/src/scrcpy_session_impl.dart`

- [ ] **Step 1: Create scrcpy_session.dart**

Create `packages/scrcpy_client/lib/src/scrcpy_session.dart`:

```dart
import 'package:scrcpy_client/src/control_message.dart';

/// Abstraction over a scrcpy mirroring session.
///
/// Pure-Dart contract: no Flutter or HTTP-proxy concerns.
/// Flutter consumers use [ScrcpyViewController] which adds
/// proxy/WebSocket server management on top.
abstract class ScrcpySession {
  /// Whether a mirroring session is currently active.
  bool get isConnected;

  /// The width of the scrcpy video stream, or `null` if no metadata yet.
  ///
  /// scrcpy may scale device frames (e.g. via `max_size`) so this can
  /// differ from the device's logical resolution. Touch/scroll control
  /// messages are silently dropped by the scrcpy server when the
  /// `width`/`height` they report do not equal the video size, so callers
  /// using device-resolution coordinates must rescale to this size.
  int? get videoWidth;

  /// The height of the scrcpy video stream, or `null` if no metadata yet.
  /// See [videoWidth].
  int? get videoHeight;

  /// Starts a mirroring session for [deviceId].
  Future<void> start(String deviceId);

  /// Stops the active mirroring session.
  Future<void> stop();

  /// Sends a raw control message to the device.
  void sendControlMessage(ScrcpyControlMessage message);

  /// Injects text into the focused field on the device.
  void injectText(String text);
}
```

- [ ] **Step 2: Create scrcpy_session_impl.dart**

Create `packages/scrcpy_client/lib/src/scrcpy_session_impl.dart`:

```dart
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_adb.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_server.dart';
import 'package:scrcpy_client/src/scrcpy_session.dart';

/// Pure-Dart implementation of [ScrcpySession] wrapping [ScrcpyServer].
///
/// No Flutter dependency — safe for use in CLI tools and MCP servers.
/// For Flutter consumers, use [ScrcpyViewController] which extends
/// `ChangeNotifier` and manages proxy/WebSocket server lifecycle.
class ScrcpySessionImpl implements ScrcpySession {
  ScrcpySessionImpl({
    required ScrcpyAdb adb,
    required Uint8List serverJarBytes,
  })  : _adb = adb,
        _serverJarBytes = serverJarBytes;

  final ScrcpyAdb _adb;
  final Uint8List _serverJarBytes;

  ScrcpyServer? _server;
  bool _running = false;
  bool _pending = false;
  void Function()? _onStopped;

  /// Whether the UI should consider the current session running.
  bool get running => _running;
  set running(bool value) => _running = value;

  @override
  bool get isConnected => _server != null;

  /// Whether a session is starting or active.
  bool get isActive => _pending || _server != null;

  /// The active [ScrcpyServer], or `null` if no session is active.
  ScrcpyServer? get server => _server;

  @override
  int? get videoWidth => _server?.currentMetadata?.width;

  @override
  int? get videoHeight => _server?.currentMetadata?.height;

  Future<List<String>> getDevices() => _adb.getDevices();

  @override
  Future<void> start(
    String deviceId, {
    ScrcpyLogger? logger,
    void Function()? onStarted,
    void Function()? onStopped,
    void Function(String)? onError,
  }) async {
    if (_pending || _server != null) return;
    _pending = true;
    _onStopped = onStopped;

    final server = ScrcpyServer(
      adb: _adb,
      deviceId: deviceId,
      serverJarBytes: _serverJarBytes,
      logger: logger ?? const NoOpScrcpyLogger(),
    );
    try {
      await server.start();
      _server = server;
      _pending = false;
      onStarted?.call();
    } on Exception catch (e) {
      onError?.call(e.toString());
      rethrow;
    } finally {
      _pending = false;
      _onStopped = null;
    }
  }

  @override
  Future<void> stop() async {
    final server = _server;
    final onStopped = _onStopped;
    _server = null;
    _pending = false;
    _onStopped = null;
    await server?.stop();
    onStopped?.call();
  }

  @override
  void sendControlMessage(ScrcpyControlMessage message) {
    _server?.sendControlMessage(message);
  }

  void injectKey(int keycode, {int metastate = 0}) {
    sendControlMessage(ScrcpyInjectKeyMessage(
      action: ScrcpyAction.down,
      keycode: keycode,
      metastate: metastate,
    ));
    sendControlMessage(ScrcpyInjectKeyMessage(
      action: ScrcpyAction.up,
      keycode: keycode,
      metastate: metastate,
    ));
  }

  @override
  void injectText(String text) {
    sendControlMessage(ScrcpyInjectTextMessage(text));
  }

  /// Creates a [ScrcpySessionImpl] by resolving the JAR asset from the
  /// filesystem.
  ///
  /// If [assetsPath] is provided, the JAR is loaded from that directory.
  /// Otherwise, the JAR is located relative to this package's source via
  /// [Isolate.resolvePackageUri].
  static Future<ScrcpySessionImpl> create({
    required ScrcpyAdb adb,
    String? assetsPath,
  }) async {
    Uint8List serverJar;

    if (assetsPath != null) {
      serverJar = await File(
        p.join(assetsPath, 'scrcpy-server-v${ScrcpyServer.serverVersion}'),
      ).readAsBytes();
    } else {
      final libUri = await Isolate.resolvePackageUri(
        Uri.parse('package:scrcpy_client/scrcpy_client.dart'),
      );
      if (libUri == null) {
        throw StateError(
          'Cannot resolve scrcpy_client package path. '
          'Use the --assets-path argument to specify the assets directory.',
        );
      }
      final packageRoot = libUri.resolve('../');
      serverJar = await File.fromUri(
        packageRoot.resolve(
          'assets/scrcpy-server-v${ScrcpyServer.serverVersion}',
        ),
      ).readAsBytes();
    }

    return ScrcpySessionImpl(adb: adb, serverJarBytes: serverJar);
  }
}
```

- [ ] **Step 3: Verify**

```bash
cd /Users/hao/ai/mobile/asf_dev && dart analyze packages/scrcpy_client/lib/src/scrcpy_session.dart packages/scrcpy_client/lib/src/scrcpy_session_impl.dart
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add packages/scrcpy_client/lib/src/scrcpy_session.dart \
        packages/scrcpy_client/lib/src/scrcpy_session_impl.dart
git commit -m "feat(scrcpy_client): add ScrcpySession interface and ScrcpySessionImpl"
```

---

## Task 6: Write the public barrel, move JAR asset, bootstrap

**Files:**
- Modify: `packages/scrcpy_client/lib/scrcpy_client.dart`
- Move: `scrcpy_view/assets/scrcpy-server-v3.3.4` → `packages/scrcpy_client/assets/scrcpy-server-v3.3.4`
- Modify: `packages/scrcpy_client/pubspec.yaml` (add flutter assets section)

- [ ] **Step 1: Write the public barrel**

Replace the empty `packages/scrcpy_client/lib/scrcpy_client.dart` with:

```dart
/// Pure-Dart client for the scrcpy Android screen-mirroring protocol.
library;

export 'src/android_metastate.dart';
export 'src/control_message.dart';
export 'src/scrcpy_adb.dart';
export 'src/scrcpy_logger.dart';
export 'src/scrcpy_packet.dart';
export 'src/scrcpy_server.dart';
export 'src/scrcpy_session.dart';
export 'src/scrcpy_session_impl.dart';
export 'src/scrcpy_stream_parser.dart';
```

- [ ] **Step 2: Move the JAR asset**

```bash
git mv scrcpy_view/assets/scrcpy-server-v3.3.4 packages/scrcpy_client/assets/scrcpy-server-v3.3.4
```

- [ ] **Step 3: Declare asset in scrcpy_client pubspec.yaml**

Add flutter section to `packages/scrcpy_client/pubspec.yaml`:

```yaml
name: scrcpy_client
description: >-
  Pure-Dart client for the scrcpy Android screen-mirroring protocol.
  Handles ADB orchestration, socket communication, video stream parsing,
  and control message injection.
version: 0.1.0
homepage: https://github.com/sunbird89629/autoglm_scrcpy_flutter

environment:
  sdk: ^3.5.0

resolution: workspace

dependencies:
  path: ^1.9.0

dev_dependencies:
  test: any

flutter:
  assets:
    - assets/scrcpy-server-v3.3.4
```

- [ ] **Step 4: Bootstrap**

```bash
cd /Users/hao/ai/mobile/asf_dev && melos bootstrap
```

Expected: resolves without errors.

- [ ] **Step 5: Analyze the full package**

```bash
cd /Users/hao/ai/mobile/asf_dev && dart analyze packages/scrcpy_client/
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add packages/scrcpy_client/lib/scrcpy_client.dart \
        packages/scrcpy_client/assets/ \
        packages/scrcpy_client/pubspec.yaml
git commit -m "feat(scrcpy_client): write barrel, move JAR asset, declare flutter assets"
```

---

## Task 7: Update scrcpy_view to depend on scrcpy_client

Add `scrcpy_client` dependency to `scrcpy_view/pubspec.yaml`, update all internal imports that now live in `scrcpy_client`.

**Files:**
- Modify: `scrcpy_view/pubspec.yaml`
- Modify: `scrcpy_view/lib/src/scrcpy_proxy_server.dart`
- Modify: `scrcpy_view/lib/src/scrcpy_websocket_server.dart`
- Modify: `scrcpy_view/lib/src/scrcpy_metastate_flutter.dart`
- Modify: `scrcpy_view/lib/src/scrcpy_view.dart`

- [ ] **Step 1: Add scrcpy_client dep to scrcpy_view/pubspec.yaml**

In `scrcpy_view/pubspec.yaml`, add to `dependencies:`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_inappwebview: ^6.1.5
  path: ^1.9.0
  scrcpy_client:
    path: ../packages/scrcpy_client
  shelf: ^1.4.2
  shelf_static: ^1.1.3
  shelf_web_socket: ^3.0.0
  web_socket_channel: ^3.0.3
```

- [ ] **Step 2: Update scrcpy_proxy_server.dart imports**

In `scrcpy_view/lib/src/scrcpy_proxy_server.dart`, replace:
```dart
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_packet.dart';
```
with:
```dart
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_packet.dart';
```

- [ ] **Step 3: Update scrcpy_websocket_server.dart imports**

In `scrcpy_view/lib/src/scrcpy_websocket_server.dart`, replace:
```dart
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_packet.dart';
```
with:
```dart
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_packet.dart';
```

- [ ] **Step 4: Update scrcpy_metastate_flutter.dart import**

`scrcpy_view/lib/src/scrcpy_metastate_flutter.dart` already imports `package:scrcpy_client/src/android_metastate.dart` (written that way in Task 3). Verify the import is correct — no change needed.

- [ ] **Step 5: Update scrcpy_view.dart (the widget) imports**

In `scrcpy_view/lib/src/scrcpy_view.dart`, update:
```dart
// Before:
import 'package:scrcpy_view/src/scrcpy_keycode.dart';
import 'package:scrcpy_view/src/scrcpy_metastate.dart';

// After:
import 'package:scrcpy_view/src/scrcpy_keycode_flutter.dart';
import 'package:scrcpy_view/src/scrcpy_metastate_flutter.dart';
```

Also update `control_message.dart` import:
```dart
import 'package:scrcpy_client/src/control_message.dart';
```

- [ ] **Step 6: Bootstrap and verify**

```bash
cd /Users/hao/ai/mobile/asf_dev && melos bootstrap && flutter analyze scrcpy_view/lib/src/scrcpy_proxy_server.dart scrcpy_view/lib/src/scrcpy_websocket_server.dart scrcpy_view/lib/src/scrcpy_view.dart
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add scrcpy_view/pubspec.yaml \
        scrcpy_view/lib/src/scrcpy_proxy_server.dart \
        scrcpy_view/lib/src/scrcpy_websocket_server.dart \
        scrcpy_view/lib/src/scrcpy_view.dart
git commit -m "refactor(scrcpy_view): depend on scrcpy_client, update imports"
```

---

## Task 8: Refactor ScrcpyViewController (add proxy/ws lifecycle management)

`ScrcpyViewController` takes over managing `ScrcpyProxyServer` and `ScrcpyWebsocketServer`, which were previously managed inside `ScrcpyServer`. It also updates asset loading (JAR from `scrcpy_client`, web player from `scrcpy_view`) and updates `scrcpy_view.dart` widget to read `playerUrl` from the controller instead of `server.playerUrl`.

**Files:**
- Modify: `scrcpy_view/lib/src/scrcpy_view_controller.dart`
- Modify: `scrcpy_view/lib/src/scrcpy_view.dart`
- Modify: `scrcpy_view/lib/src/backends/scrcpy_video_backend.dart`

- [ ] **Step 1: Rewrite ScrcpyViewController**

Replace the full content of `scrcpy_view/lib/src/scrcpy_view_controller.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_adb.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_server.dart';
import 'package:scrcpy_client/src/scrcpy_session.dart';
import 'package:scrcpy_client/src/scrcpy_session_impl.dart';
import 'package:scrcpy_view/src/backends/scrcpy_video_backend.dart';
import 'package:scrcpy_view/src/scrcpy_proxy_server.dart';
import 'package:scrcpy_view/src/scrcpy_websocket_server.dart';

/// Controller for `ScrcpyView` that owns the device mirroring session,
/// manages the HTTP/WebSocket proxy servers, and exposes input injection.
///
/// Create an instance, call [start] to begin mirroring, and pass the
/// controller to `ScrcpyView`. Call [stop] to end the session. Dispose
/// when the controller is no longer needed.
///
/// Example:
/// ```dart
/// final controller = ScrcpyViewController(adb: myAdb);
/// await controller.start('11081FDD4004DY');
/// ScrcpyView(controller: controller)
/// // Later:
/// controller.injectKey(ScrcpyKeycode.home);
/// await controller.stop();
/// controller.dispose();
/// ```
class ScrcpyViewController extends ChangeNotifier implements ScrcpySession {
  ScrcpyViewController({required ScrcpyAdb adb}) : _adb = adb {
    PlatformInAppWebViewController.debugLoggingSettings.excludeFilter
        .add(RegExp('statsHandler'));
  }

  final ScrcpyAdb _adb;

  ScrcpySessionImpl? _impl;
  ScrcpyProxyServer? _proxy;
  ScrcpyWebsocketServer? _wsProxy;

  String? _proxyUrl;
  String? _playerUrl;

  /// Touch event forwarder passed to the video backend.
  // ignore: prefer_function_declarations_over_variables
  late final ScrcpyTouchCallback touchController =
      (msg) => _impl?.sendControlMessage(msg);

  Future<List<String>> getDevices() =>
      _impl?.getDevices() ?? _adb.getDevices();

  // ── Readable state ────────────────────────────────────────────────────────

  bool get running => _impl?.running ?? false;

  set running(bool value) {
    if (_impl != null) _impl!.running = value;
    notifyListeners();
  }

  @override
  bool get isConnected => _impl != null;

  bool get isActive => _impl?.isActive ?? false;

  ScrcpyServer? get server => _impl?.server;

  /// HTTP proxy URL for MPEG-TS stream (media_kit), or `null` if not started.
  String? get proxyUrl => _proxyUrl;

  /// WebSocket player URL (web-based player), or `null` if not started.
  String? get playerUrl => _playerUrl;

  /// Resolves after the proxy has buffered SPS/PPS + first keyframe.
  Future<void> get proxyReady => _proxy?.ready ?? Future.value();

  @override
  int? get videoWidth => _impl?.videoWidth;

  @override
  int? get videoHeight => _impl?.videoHeight;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> start(
    String deviceId, {
    ScrcpyLogger? logger,
    VoidCallback? onStarted,
    VoidCallback? onStopped,
    ValueChanged<String>? onError,
  }) async {
    if (_impl != null) return;
    notifyListeners();

    try {
      final version = ScrcpyServer.serverVersion;

      // JAR now lives in scrcpy_client assets.
      final serverJarData = await rootBundle.load(
        'packages/scrcpy_client/assets/scrcpy-server-v$version',
      );
      final serverJarBytes = serverJarData.buffer.asUint8List();

      // Web player stays in scrcpy_view assets.
      final webPlayerData = await rootBundle.load(
        'packages/scrcpy_view/assets/web_player/index.html',
      );
      final webPlayerBytes = webPlayerData.buffer.asUint8List();

      _impl = ScrcpySessionImpl(adb: _adb, serverJarBytes: serverJarBytes);

      // ScrcpySessionImpl.start() blocks until sockets are connected.
      await _impl!.start(deviceId,
          logger: logger, onStopped: onStopped, onError: onError);

      // Wire up proxy servers directly here (not inside an async onStarted
      // callback) so we can safely await each step.
      final srv = _impl!.server!;
      final webPlayerPath = await _prepareWebPlayer(webPlayerBytes);
      final effectiveLogger = logger ?? const NoOpScrcpyLogger();
      _proxy = ScrcpyProxyServer(logger: effectiveLogger);
      _wsProxy = ScrcpyWebsocketServer(logger: effectiveLogger);

      await Future.wait([
        _proxy!.start(srv.packets),
        _wsProxy!.start(srv.packets, staticPath: webPlayerPath),
      ]);

      _proxyUrl = _proxy!.proxyUrl;
      _playerUrl = _wsProxy!.playerUrl;

      // Stop proxies automatically if the server process exits unexpectedly.
      srv.packets.listen(null, onDone: _stopProxies);

      notifyListeners();
      onStarted?.call();
    } catch (e) {
      _impl = null;
      await _stopProxies();
      notifyListeners();
      onError?.call(e.toString());
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final impl = _impl;
    _impl = null;
    notifyListeners();
    await _stopProxies();
    await impl?.stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ── Control API ───────────────────────────────────────────────────────────

  @override
  void sendControlMessage(ScrcpyControlMessage message) {
    _impl?.sendControlMessage(message);
  }

  void injectKey(int keycode, {int metastate = 0}) {
    _impl?.injectKey(keycode, metastate: metastate);
  }

  @override
  void injectText(String text) {
    _impl?.injectText(text);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _stopProxies() async {
    final proxy = _proxy;
    final wsProxy = _wsProxy;
    _proxy = null;
    _wsProxy = null;
    _proxyUrl = null;
    _playerUrl = null;
    await proxy?.stop();
    await wsProxy?.stop();
  }

  Future<String> _prepareWebPlayer(Uint8List webPlayerBytes) async {
    final tempDir = Directory.systemTemp;
    final webDir = Directory(p.join(tempDir.path, 'autoglm_web_player'))
      ..createSync(recursive: true);
    await File(p.join(webDir.path, 'index.html'))
        .writeAsBytes(webPlayerBytes, flush: true);
    return webDir.path;
  }
}
```

- [ ] **Step 2: Update scrcpy_view.dart widget — use controller.playerUrl instead of server.playerUrl**

In `scrcpy_view/lib/src/scrcpy_view.dart`, the `build` method currently accesses `widget.controller.server` and then `server.playerUrl`. After the refactor `ScrcpyServer` no longer has `playerUrl`. Replace the build body:

```dart
@override
Widget build(BuildContext context) {
  return ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final playerUrl = widget.controller.playerUrl;
      if (playerUrl == null) {
        return const Center(child: Text('点击 Start 启动服务'));
      }
      return Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: GestureDetector(
          onTap: _focusNode.requestFocus,
          child: WebViewVideoPlayer(
            playerUrl: playerUrl,
            touchController: widget.controller.touchController,
            onControlMessage: widget.controller.sendControlMessage,
          ),
        ),
      );
    },
  );
}
```

Also update the imports in `scrcpy_view/lib/src/scrcpy_view.dart`:
```dart
import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_keycode_flutter.dart';
import 'package:scrcpy_view/src/scrcpy_metastate_flutter.dart';
import 'package:scrcpy_view/src/scrcpy_view_controller.dart';
import 'package:scrcpy_view/webview_video_player.dart';
```
(Remove the old `scrcpy_view/src/control_message.dart`, `scrcpy_keycode.dart`, `scrcpy_metastate.dart` imports.)

- [ ] **Step 3: Update scrcpy_video_backend.dart import**

In `scrcpy_view/lib/src/backends/scrcpy_video_backend.dart`, replace:
```dart
import 'package:scrcpy_view/src/control_message.dart';
```
with:
```dart
import 'package:scrcpy_client/src/control_message.dart';
```

- [ ] **Step 4: Verify**

```bash
cd /Users/hao/ai/mobile/asf_dev && flutter analyze scrcpy_view/lib/src/scrcpy_view_controller.dart scrcpy_view/lib/src/scrcpy_view.dart scrcpy_view/lib/src/backends/
```

Expected: No issues found (info-level existing issues acceptable).

- [ ] **Step 5: Commit**

```bash
git add scrcpy_view/lib/src/scrcpy_view_controller.dart \
        scrcpy_view/lib/src/scrcpy_view.dart \
        scrcpy_view/lib/src/backends/scrcpy_video_backend.dart
git commit -m "refactor(scrcpy_view): ScrcpyViewController owns proxy/ws lifecycle"
```

---

## Task 9: Update scrcpy_view barrels and delete migrated source files

Update the two barrels (`scrcpy_view.dart`, `scrcpy_core.dart`) and delete the original source files that now live in `scrcpy_client`.

**Files:**
- Modify: `scrcpy_view/lib/scrcpy_view.dart`
- Delete: `scrcpy_view/lib/scrcpy_core.dart`
- Delete: `scrcpy_view/lib/src/control_message.dart`
- Delete: `scrcpy_view/lib/src/scrcpy_adb.dart`
- Delete: `scrcpy_view/lib/src/scrcpy_logger.dart`
- Delete: `scrcpy_view/lib/src/scrcpy_packet.dart`
- Delete: `scrcpy_view/lib/src/scrcpy_stream_parser.dart`
- Delete: `scrcpy_view/lib/src/scrcpy_server.dart`
- Delete: `scrcpy_view/lib/src/scrcpy_session.dart`
- Delete: `scrcpy_view/lib/src/scrcpy_session_impl.dart`

- [ ] **Step 1: Rewrite scrcpy_view.dart barrel**

Replace the full content of `scrcpy_view/lib/scrcpy_view.dart`:

```dart
/// Scrcpy protocol and embeddable Flutter widget for Android screen mirroring.
library;

// Re-export the pure-Dart protocol layer for convenience.
export 'package:scrcpy_client/scrcpy_client.dart';

// Flutter-specific additions.
export 'src/backends/scrcpy_video_backend.dart';
export 'src/nav_buttons.dart';
export 'src/scrcpy_keycode_flutter.dart';
export 'src/scrcpy_metastate_flutter.dart';
export 'src/scrcpy_proxy_server.dart';
export 'src/scrcpy_view_controller.dart';
export 'src/scrcpy_view.dart';
export 'src/scrcpy_websocket_server.dart';
export 'src/scrcpy_stream_parser.dart';
```

Wait — `scrcpy_stream_parser.dart` is in `scrcpy_client` now. Remove the direct export and keep only the re-export via `scrcpy_client.dart`. The correct barrel:

```dart
/// Scrcpy protocol and embeddable Flutter widget for Android screen mirroring.
library;

// Re-export the pure-Dart protocol layer for convenience.
export 'package:scrcpy_client/scrcpy_client.dart';

// Flutter-specific additions.
export 'src/backends/scrcpy_video_backend.dart';
export 'src/nav_buttons.dart';
export 'src/scrcpy_keycode_flutter.dart';
export 'src/scrcpy_metastate_flutter.dart';
export 'src/scrcpy_proxy_server.dart';
export 'src/scrcpy_view_controller.dart';
export 'src/scrcpy_view.dart';
export 'src/scrcpy_websocket_server.dart';
```

- [ ] **Step 2: Delete scrcpy_core.dart** (replaced by `package:scrcpy_client/scrcpy_client.dart`)

```bash
git rm scrcpy_view/lib/scrcpy_core.dart
```

- [ ] **Step 3: Delete migrated source files from scrcpy_view/src/**

```bash
git rm scrcpy_view/lib/src/control_message.dart \
       scrcpy_view/lib/src/scrcpy_adb.dart \
       scrcpy_view/lib/src/scrcpy_logger.dart \
       scrcpy_view/lib/src/scrcpy_packet.dart \
       scrcpy_view/lib/src/scrcpy_stream_parser.dart \
       scrcpy_view/lib/src/scrcpy_server.dart \
       scrcpy_view/lib/src/scrcpy_session.dart \
       scrcpy_view/lib/src/scrcpy_session_impl.dart
```

- [ ] **Step 4: Analyze scrcpy_view fully**

```bash
cd /Users/hao/ai/mobile/asf_dev && flutter analyze scrcpy_view/
```

Expected: No errors (existing info-level issues acceptable).

- [ ] **Step 5: Commit**

```bash
git add scrcpy_view/lib/scrcpy_view.dart
git commit -m "refactor(scrcpy_view): update barrels, delete migrated source files"
```

---

## Task 10: Update scrcpy_mcp to depend on scrcpy_client

Replace `scrcpy_view` dependency with `scrcpy_client` in `scrcpy_mcp`, update all import paths.

**Files:**
- Modify: `scrcpy_mcp/pubspec.yaml`
- Modify: all `scrcpy_mcp/lib/src/*.dart` and `scrcpy_mcp/bin/scrcpy_mcp.dart` that import `scrcpy_view`

- [ ] **Step 1: Update scrcpy_mcp/pubspec.yaml**

Replace `scrcpy_view` with `scrcpy_client`:

```yaml
name: scrcpy_mcp
description: MCP server for scrcpy — Android screen mirroring via MCP protocol.
publish_to: none
version: 0.2.0

environment:
  sdk: ^3.5.0

resolution: workspace

dependencies:
  adb_tools:
    path: ../packages/adb_tools
  logger_utils:
    path: ../packages/logger_utils
  mcp_dart: ^2.1.1
  scrcpy_client:
    path: ../packages/scrcpy_client
```

- [ ] **Step 2: Update all imports in scrcpy_mcp**

All files that currently import `package:scrcpy_view/scrcpy_core.dart` need to change to `package:scrcpy_client/scrcpy_client.dart`. Run:

```bash
grep -rl "scrcpy_view" /Users/hao/ai/mobile/asf_dev/scrcpy_mcp/lib/ \
                       /Users/hao/ai/mobile/asf_dev/scrcpy_mcp/bin/ \
                       /Users/hao/ai/mobile/asf_dev/scrcpy_mcp/test/
```

For each file found, replace:
```dart
import 'package:scrcpy_view/scrcpy_core.dart';
```
with:
```dart
import 'package:scrcpy_client/scrcpy_client.dart';
```

- [ ] **Step 3: Bootstrap and verify**

```bash
cd /Users/hao/ai/mobile/asf_dev && melos bootstrap && dart analyze scrcpy_mcp/
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_mcp/pubspec.yaml scrcpy_mcp/lib/ scrcpy_mcp/bin/ scrcpy_mcp/test/
git commit -m "refactor(scrcpy_mcp): depend on scrcpy_client instead of scrcpy_view"
```

---

## Task 11: Move tests to scrcpy_client/test/ and update them

The existing `control_message_test.dart` and `control_send_test.dart` in `scrcpy_view/test/` are pure Dart tests. Move them to `scrcpy_client/test/`, switch from `flutter_test` to `test`, and remove the `webPlayerBytes` argument that no longer exists on `ScrcpyServer`.

**Files:**
- Create: `packages/scrcpy_client/test/control_message_test.dart`
- Create: `packages/scrcpy_client/test/control_send_test.dart`
- Delete: `scrcpy_view/test/control_message_test.dart`
- Delete: `scrcpy_view/test/control_send_test.dart`

- [ ] **Step 1: Create scrcpy_client/test/control_message_test.dart**

Copy from `scrcpy_view/test/control_message_test.dart` and change:
- `import 'package:flutter_test/flutter_test.dart';` → `import 'package:test/test.dart';`
- `import 'package:scrcpy_view/src/control_message.dart';` → `import 'package:scrcpy_client/src/control_message.dart';`

Full content of `packages/scrcpy_client/test/control_message_test.dart`:

```dart
import 'dart:typed_data';

import 'package:scrcpy_client/src/control_message.dart';
import 'package:test/test.dart';

void main() {
  group('ScrcpyInjectTouchMessage', () {
    test('binary layout matches scrcpy v3 ControlMessageReader (32 bytes)', () {
      const msg = ScrcpyInjectTouchMessage(
        action: ScrcpyAction.down,
        pointerId: 0xDEADBEEFCAFEBABE,
        x: 540,
        y: 960,
        width: 1080,
        height: 1920,
      );

      final bytes = msg.toBinary();

      expect(bytes.length, 32);
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 2);
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint64(2), 0xDEADBEEFCAFEBABE);
      expect(bd.getUint32(10), 540);
      expect(bd.getUint32(14), 960);
      expect(bd.getUint16(18), 1080);
      expect(bd.getUint16(20), 1920);
      expect(bd.getUint16(22), 65535);
      expect(bd.getUint32(24), 0);
      expect(bd.getUint32(28), 0);
    });

    test('pressure maps [0.0, 1.0] to uint16 [0, 65535]', () {
      expectPressure(0, 0);
      expectPressure(0.5, 32767);
      expectPressure(1, 65535);
      expectPressure(1.5, 65535);
      expectPressure(-0.5, 0);
    });

    test('action constants: down=0, up=1, move=2, cancel=3', () {
      final actions = [
        (ScrcpyAction.down, 0),
        (ScrcpyAction.up, 1),
        (ScrcpyAction.move, 2),
        (ScrcpyAction.cancel, 3),
      ];
      for (final (action, expected) in actions) {
        final bytes = ScrcpyInjectTouchMessage(
          action: action,
          pointerId: 0,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ).toBinary();
        expect(bytes[1], expected,
            reason: 'action $action should encode as $expected');
      }
    });

    test('actionButton and buttons are encoded at correct offsets', () {
      const msg = ScrcpyInjectTouchMessage(
        action: ScrcpyAction.down,
        pointerId: 0,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        actionButton: 0x01,
        buttons: 0x01000000,
      );
      final bd = ByteData.sublistView(msg.toBinary());
      expect(bd.getUint32(24), 0x01);
      expect(bd.getUint32(28), 0x01000000);
    });
  });

  group('ScrcpyInjectKeyMessage', () {
    test('binary layout is 14 bytes with correct field offsets', () {
      const msg = ScrcpyInjectKeyMessage(
        action: ScrcpyAction.down,
        keycode: ScrcpyKeycode.home,
      );

      final bytes = msg.toBinary();
      expect(bytes.length, 14);
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 0);
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint32(2), ScrcpyKeycode.home);
      expect(bd.getUint32(6), 0);
      expect(bd.getUint32(10), 0);
    });

    test('keycodes: home=3, back=4, appSwitch=187', () {
      for (final (keycode, expected) in [
        (ScrcpyKeycode.home, 3),
        (ScrcpyKeycode.back, 4),
        (ScrcpyKeycode.appSwitch, 187),
      ]) {
        final msg = ScrcpyInjectKeyMessage(
          action: ScrcpyAction.down,
          keycode: keycode,
        );
        final bd = ByteData.sublistView(msg.toBinary());
        expect(bd.getUint32(2), expected, reason: 'keycode $keycode mismatch');
      }
    });
  });

  group('ScrcpyInjectTextMessage', () {
    test('UTF-8 text is encoded with 4-byte length prefix', () {
      const text = 'hello';
      const msg = ScrcpyInjectTextMessage(text);

      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 1);
      expect(bd.getUint32(1), text.length);
      final payload = bytes.sublist(5);
      expect(payload, text.codeUnits);
    });

    test('handles empty string', () {
      final bytes = const ScrcpyInjectTextMessage('').toBinary();
      expect(bytes.length, 5);
      expect(ByteData.sublistView(bytes).getUint32(1), 0);
    });

    test('handles multi-byte UTF-8 characters', () {
      const text = '你好';
      final bytes = const ScrcpyInjectTextMessage(text).toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint32(1), 6);
      expect(bytes.length, 5 + 6);
    });
  });

  group('ScrcpyInjectScrollMessage', () {
    test('binary layout is 21 bytes with i16fp-encoded scroll values', () {
      const msg = ScrcpyInjectScrollMessage(
        x: 100, y: 200, width: 1080, height: 1920,
        hScroll: -10, vScroll: 50,
      );

      final bytes = msg.toBinary();
      expect(bytes.length, 21);
      final bd = ByteData.sublistView(bytes);

      expect(bd.getUint8(0), 3);
      expect(bd.getUint32(1), 100);
      expect(bd.getUint32(5), 200);
      expect(bd.getUint16(9), 1080);
      expect(bd.getUint16(11), 1920);
      expect(bd.getInt16(13), -20479);
      expect(bd.getInt16(15), 32767);
      expect(bd.getUint32(17), 0);
    });

    test('values clamped to max scroll magnitude outside [-16, 16]', () {
      const msg = ScrcpyInjectScrollMessage(
        x: 0, y: 0, width: 1080, height: 1920,
        hScroll: -100, vScroll: 100,
      );
      final bd = ByteData.sublistView(msg.toBinary());
      expect(bd.getInt16(13), -32767);
      expect(bd.getInt16(15), 32767);
    });
  });

  group('ScrcpySetClipboardMessage', () {
    test('binary layout: type=9, sequence(8), paste(1), text_len(4), utf8', () {
      const msg = ScrcpySetClipboardMessage(text: 'hello', sequence: 1);
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bytes.length, 14 + 5);
      expect(bd.getUint8(0), 9);
      expect(bd.getUint64(1), 1);
      expect(bd.getUint8(9), 1);
      expect(bd.getUint32(10), 5);
      expect(bytes.sublist(14), 'hello'.codeUnits);
    });

    test('Chinese text: text_len reflects UTF-8 byte count, not char count', () {
      const msg = ScrcpySetClipboardMessage(text: '你好');
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);

      expect(bytes.length, 14 + 6);
      expect(bd.getUint32(10), 6);
    });

    test('paste=false encodes paste byte as 0', () {
      const msg = ScrcpySetClipboardMessage(text: 'x', paste: false);
      final bd = ByteData.sublistView(msg.toBinary());
      expect(bd.getUint8(9), 0);
    });

    test('empty text produces 14-byte message with text_len=0', () {
      const msg = ScrcpySetClipboardMessage(text: '');
      final bytes = msg.toBinary();
      final bd = ByteData.sublistView(bytes);
      expect(bytes.length, 14);
      expect(bd.getUint32(10), 0);
    });

    test('sequence is encoded as uint64 at offset 1', () {
      const msg = ScrcpySetClipboardMessage(
        text: '', sequence: 0xDEADBEEFCAFEBABE,
      );
      final bd = ByteData.sublistView(msg.toBinary());
      expect(bd.getUint64(1), 0xDEADBEEFCAFEBABE);
    });
  });

  group('ScrcpyBackOrScreenOnMessage', () {
    test('binary layout is 2 bytes', () {
      final bytes =
          const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down).toBinary();
      expect(bytes.length, 2);
      expect(bytes[0], 4);
      expect(bytes[1], ScrcpyAction.down);
    });
  });
}

void expectPressure(double input, int expected) {
  final msg = ScrcpyInjectTouchMessage(
    action: ScrcpyAction.down,
    pointerId: 0, x: 0, y: 0, width: 1, height: 1,
    pressure: input,
  );
  final bd = ByteData.sublistView(msg.toBinary());
  expect(bd.getUint16(22), expected,
      reason: 'pressure $input should encode as $expected');
}
```

- [ ] **Step 2: Create scrcpy_client/test/control_send_test.dart**

`ScrcpyServer` constructor no longer takes `webPlayerBytes`. Update the helper accordingly.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_adb.dart';
import 'package:scrcpy_client/src/scrcpy_server.dart';
import 'package:test/test.dart';

class _NoOpAdb implements ScrcpyAdb {
  const _NoOpAdb();

  @override
  String get adbPath => 'adb';

  @override
  Future<List<String>> getDevices() async => [];

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async => ProcessResult(0, 0, '', '');

  @override
  Future<void> forward(String local, String remote,
      {String? deviceId, bool noRebind = false}) async {}

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {}

  @override
  Future<void> push(String localPath, String remotePath,
      {String? deviceId}) async {}

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async => Uint8List(0);
}

void main() {
  (ScrcpyServer, List<List<int>>) createServer() {
    final captured = <List<int>>[];
    final controller = StreamController<List<int>>(sync: true);
    controller.stream.listen(captured.add);
    final server = ScrcpyServer(
      adb: const _NoOpAdb(),
      deviceId: 'test-device',
      serverJarBytes: Uint8List(0),
      // webPlayerBytes removed — proxy servers are managed by ScrcpyViewController
      controlSink: controller.sink,
    );
    return (server, captured);
  }

  group('sendControlMessage via injected sink', () {
    test('touch message (type 2) writes 32 bytes', () {
      final (server, captured) = createServer();
      server.sendControlMessage(const ScrcpyInjectTouchMessage(
        action: ScrcpyAction.down, pointerId: 1,
        x: 100, y: 200, width: 1080, height: 1920,
      ));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 32);
      expect(bd.getUint8(0), 2);
      expect(bd.getUint8(1), ScrcpyAction.down);
    });

    test('keycode message (type 0) writes 14 bytes', () {
      final (server, captured) = createServer();
      server.sendControlMessage(const ScrcpyInjectKeyMessage(
        action: ScrcpyAction.down, keycode: ScrcpyKeycode.home,
      ));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 14);
      expect(bd.getUint8(0), 0);
      expect(bd.getUint8(1), ScrcpyAction.down);
      expect(bd.getUint32(2), ScrcpyKeycode.home);
    });

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

    test('scroll message (type 3) writes 21 bytes', () {
      final (server, captured) = createServer();
      server.sendControlMessage(const ScrcpyInjectScrollMessage(
        x: 100, y: 200, width: 1080, height: 1920,
        hScroll: -10, vScroll: 50,
      ));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 21);
      expect(bd.getUint8(0), 3);
      expect(bd.getInt16(13), -20479);
      expect(bd.getInt16(15), 32767);
    });

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

    test('set-clipboard with paste=false sends 0 at paste offset', () {
      final (server, captured) = createServer();
      server.sendControlMessage(
          const ScrcpySetClipboardMessage(text: 'abc', paste: false));
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(bd.getUint8(9), 0);
    });

    test('back-or-screen-on message (type 4) writes 2 bytes', () {
      final (server, captured) = createServer();
      server.sendControlMessage(
          const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down));
      expect(captured.length, 1);
      final bd = ByteData.sublistView(Uint8List.fromList(captured.single));
      expect(captured.single.length, 2);
      expect(bd.getUint8(0), 4);
      expect(bd.getUint8(1), ScrcpyAction.down);
    });
  });
}
```

- [ ] **Step 3: Delete old test files from scrcpy_view/test/**

```bash
git rm scrcpy_view/test/control_message_test.dart \
       scrcpy_view/test/control_send_test.dart
```

- [ ] **Step 4: Run the new tests**

```bash
cd /Users/hao/ai/mobile/asf_dev && dart test packages/scrcpy_client/test/
```

Expected:
```
00:00 +24: All tests passed!
```

- [ ] **Step 5: Commit**

```bash
git add packages/scrcpy_client/test/ scrcpy_view/test/
git commit -m "test(scrcpy_client): move control protocol tests from scrcpy_view"
```

---

## Task 12: Final verification and cleanup

**Files:** No new files. Verification only.

- [ ] **Step 1: Full workspace bootstrap**

```bash
cd /Users/hao/ai/mobile/asf_dev && melos bootstrap
```

Expected: All packages resolve, no errors.

- [ ] **Step 2: Analyze all packages**

```bash
dart analyze packages/scrcpy_client/ && \
dart analyze scrcpy_mcp/ && \
flutter analyze scrcpy_view/ scrcpy_app/
```

Expected: No errors. Existing info-level issues in `scrcpy_session_impl.dart` are acceptable.

- [ ] **Step 3: Verify Flutter transitive dep is gone from scrcpy_mcp**

```bash
dart pub deps --style=list 2>/dev/null | grep flutter || echo "No Flutter dep — PASS"
```

Run this from the `scrcpy_mcp` directory. Expected output: `No Flutter dep — PASS`.

- [ ] **Step 4: Run scrcpy_client tests**

```bash
cd /Users/hao/ai/mobile/asf_dev && dart test packages/scrcpy_client/test/
```

Expected: `+24: All tests passed!`

- [ ] **Step 5: Run scrcpy_view tests**

```bash
cd /Users/hao/ai/mobile/asf_dev && flutter test scrcpy_view/test/
```

Expected: All existing tests pass (stream parser, server, keycode, metastate tests).

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "refactor: complete scrcpy_client package extraction

scrcpy_mcp now depends on pure-Dart scrcpy_client with no Flutter
transitive dependency. scrcpy_view depends on scrcpy_client for the
protocol layer and retains only Flutter widgets and HTTP/WebSocket
proxy servers."
```
