# MCP Screen Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `start_recording`, `stop_recording` MCP tools and `recording://status` resource to `scrcpy_mcp` using `adb shell screenrecord`.

**Architecture:** A narrow `RecordingAdb` interface lives entirely inside `scrcpy_mcp`, keeping `scrcpy_view` and `scrcpy_app` untouched. `ScrcpyMcpAdb` implements both `ScrcpyAdb` and `RecordingAdb`. A `RecordingController` manages the `screenrecord` process lifecycle. Recording tools are only registered when a `RecordingAdb` is injected (opt-in), so the existing `_TestEnv` in server tests continues passing without change.

**Tech Stack:** Dart, `dart:io` (Process, File, Directory), `flutter_test`, `mcp_dart`, `autoglm_logger`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `scrcpy_mcp/lib/src/recording_adb.dart` | Create | `RecordingProcess`, `RecordingStatus`, `RecordingAdb` |
| `scrcpy_mcp/lib/src/recording_controller.dart` | Create | State machine: idle ↔ recording |
| `scrcpy_mcp/lib/src/scrcpy_mcp_adapters.dart` | Modify | `ScrcpyMcpAdb` implements `RecordingAdb`; `_RealProcess` |
| `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart` | Modify | Optional `RecordingAdb?`; register tools + resource |
| `scrcpy_mcp/lib/src/mcp_http_server.dart` | Modify | Forward optional `RecordingAdb?` to `ScrcpyMcpServer` |
| `scrcpy_mcp/lib/scrcpy_mcp.dart` | Modify | Export `recording_adb.dart` |
| `scrcpy_mcp/bin/scrcpy_mcp.dart` | Modify | Pass `scrcpyAdb` as `recordingAdb` |
| `scrcpy_mcp/test/recording_controller_test.dart` | Create | Unit tests for `RecordingController` |
| `scrcpy_mcp/test/scrcpy_mcp_server_test.dart` | Modify | Add recording tool/resource tests |

---

## Task 1: Define recording interfaces and data types

**Files:**
- Create: `scrcpy_mcp/lib/src/recording_adb.dart`
- Modify: `scrcpy_mcp/lib/scrcpy_mcp.dart`

- [ ] **Step 1: Create `scrcpy_mcp/lib/src/recording_adb.dart`**

```dart
import 'dart:io';

/// Narrow interface for the parts of a [Process] used by [RecordingController].
abstract class RecordingProcess {
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// Snapshot of the current recording state.
class RecordingStatus {
  const RecordingStatus({
    required this.isRecording,
    this.deviceId,
    this.startTime,
    this.remotePath,
  });

  final bool isRecording;
  final String? deviceId;
  final DateTime? startTime;
  final String? remotePath;

  Map<String, dynamic> toJson() => {
        'is_recording': isRecording,
        if (deviceId != null) 'device_id': deviceId,
        if (startTime != null)
          'start_time': startTime!.toUtc().toIso8601String(),
        if (remotePath != null) 'remote_path': remotePath,
      };
}

/// ADB operations required for screen recording.
abstract class RecordingAdb {
  /// Launches `adb shell screenrecord` in the background; does NOT await exit.
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  });

  /// Pulls a file from the device to the host.
  Future<void> pullFile(String deviceId, String remotePath, String localPath);

  /// Deletes a file on the device.
  Future<void> removeFile(String deviceId, String remotePath);
}
```

- [ ] **Step 2: Export the new file from `scrcpy_mcp/lib/scrcpy_mcp.dart`**

Replace full file content:

```dart
export 'src/mcp_http_server.dart';
export 'src/recording_adb.dart';
export 'src/scrcpy_mcp_adapters.dart';
export 'src/scrcpy_mcp_server.dart';
```

- [ ] **Step 3: Verify it compiles**

```bash
cd scrcpy_mcp && dart analyze lib/
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_mcp/lib/src/recording_adb.dart scrcpy_mcp/lib/scrcpy_mcp.dart
git commit -m "feat(scrcpy_mcp): add RecordingAdb interface and RecordingStatus types"
```

---

## Task 2: RecordingController — happy path (TDD)

**Files:**
- Create: `scrcpy_mcp/test/recording_controller_test.dart`
- Create: `scrcpy_mcp/lib/src/recording_controller.dart`

- [ ] **Step 1: Create the test file with mocks and initial tests**

Create `scrcpy_mcp/test/recording_controller_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_mcp/src/recording_adb.dart';
import 'package:scrcpy_mcp/src/recording_controller.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockRecordingAdb implements RecordingAdb {
  final List<(String, String)> startCalls = [];
  final List<(String, String, String)> pullCalls = [];
  final List<(String, String)> removeCalls = [];

  _FakeProcess? _lastProcess;
  Object? pullError;

  void simulateUnexpectedExit(int code) =>
      _lastProcess!._completer.complete(code);

  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    startCalls.add((deviceId, remotePath));
    _lastProcess = _FakeProcess();
    return _lastProcess!;
  }

  @override
  Future<void> pullFile(
    String deviceId,
    String remotePath,
    String localPath,
  ) async {
    pullCalls.add((deviceId, remotePath, localPath));
    final err = pullError;
    if (err != null) throw err;
  }

  @override
  Future<void> removeFile(String deviceId, String remotePath) async {
    removeCalls.add((deviceId, remotePath));
  }
}

class _FakeProcess implements RecordingProcess {
  final _completer = Completer<int>();
  bool _killed = false;

  bool get wasKilled => _killed;

  @override
  Future<int> get exitCode => _completer.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_killed) {
      _killed = true;
      if (!_completer.isCompleted) _completer.complete(0);
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RecordingController', () {
    late _MockRecordingAdb adb;
    late RecordingController ctrl;

    setUp(() {
      adb = _MockRecordingAdb();
      ctrl = RecordingController(adb);
    });

    // ── Initial state ──────────────────────────────────────────────────────

    test('isRecording is false initially', () {
      expect(ctrl.isRecording, isFalse);
    });

    test('status is idle initially', () {
      final s = ctrl.status;
      expect(s.isRecording, isFalse);
      expect(s.deviceId, isNull);
      expect(s.startTime, isNull);
      expect(s.remotePath, isNull);
    });

    // ── Start ──────────────────────────────────────────────────────────────

    test('start() sets isRecording and returns /sdcard remote path', () async {
      final remotePath = await ctrl.start('emulator-5554');

      expect(ctrl.isRecording, isTrue);
      expect(remotePath, startsWith('/sdcard/mcp_rec_'));
      expect(remotePath, endsWith('.mp4'));
    });

    test('start() passes device_id to adb', () async {
      await ctrl.start('emulator-5554');

      expect(adb.startCalls, hasLength(1));
      expect(adb.startCalls.first.$1, 'emulator-5554');
    });

    test('status reflects running recording', () async {
      await ctrl.start('emulator-5554');
      final s = ctrl.status;

      expect(s.isRecording, isTrue);
      expect(s.deviceId, 'emulator-5554');
      expect(s.startTime, isNotNull);
      expect(s.remotePath, startsWith('/sdcard/mcp_rec_'));
    });
  });
}
```

- [ ] **Step 2: Run — expect compile failure (class not yet created)**

```bash
cd scrcpy_mcp && flutter test test/recording_controller_test.dart
```

Expected: error — `recording_controller.dart` not found.

- [ ] **Step 3: Create `scrcpy_mcp/lib/src/recording_controller.dart`**

```dart
import 'dart:io';

import 'package:autoglm_logger/autoglm_logger.dart';

import 'recording_adb.dart';

class RecordingController {
  RecordingController(this._adb);

  final RecordingAdb _adb;
  RecordingProcess? _process;
  String? _deviceId;
  String? _remotePath;
  DateTime? _startTime;

  bool get isRecording => _process != null;

  RecordingStatus get status => RecordingStatus(
        isRecording: isRecording,
        deviceId: _deviceId,
        startTime: _startTime,
        remotePath: _remotePath,
      );

  Future<String> start(
    String deviceId, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    if (isRecording) {
      throw StateError('Already recording on $_deviceId since $_startTime');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final remotePath = '/sdcard/mcp_rec_$timestamp.mp4';
    final process = await _adb.startScreenrecord(
      deviceId,
      remotePath,
      bitrate: bitrate,
      maxTime: maxTime,
    );
    _process = process;
    _deviceId = deviceId;
    _remotePath = remotePath;
    _startTime = DateTime.now();

    // Monitor for unexpected exit; no-op if stop() already ran first.
    process.exitCode.then((_) {
      if (isRecording) {
        appLogger.w('screenrecord process exited unexpectedly on $deviceId');
        _reset();
      }
    });

    return remotePath;
  }

  Future<String> stop({String? savePath}) async {
    final process = _process!;
    final deviceId = _deviceId!;
    final remotePath = _remotePath!;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final localPath = savePath ?? _defaultLocalPath(timestamp);

    // Reset before async work so the exitCode monitor sees isRecording=false.
    _reset();

    process.kill(ProcessSignal.sigint);
    await process.exitCode;

    await Directory(localPath).parent.create(recursive: true);
    await _adb.pullFile(deviceId, remotePath, localPath);
    await _adb.removeFile(deviceId, remotePath);

    return localPath;
  }

  void _reset() {
    _process = null;
    _deviceId = null;
    _remotePath = null;
    _startTime = null;
  }

  String _defaultLocalPath(int timestamp) {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/Downloads/scrcpy_records/rec_$timestamp.mp4';
  }
}
```

- [ ] **Step 4: Run — expect all 5 tests to pass**

```bash
cd scrcpy_mcp && flutter test test/recording_controller_test.dart
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/lib/src/recording_controller.dart \
        scrcpy_mcp/test/recording_controller_test.dart
git commit -m "feat(scrcpy_mcp): implement RecordingController with start() and status"
```

---

## Task 3: RecordingController — stop() happy path (TDD)

**Files:**
- Modify: `scrcpy_mcp/test/recording_controller_test.dart`

- [ ] **Step 1: Append stop() tests inside the existing `group`**

Add after the `'status reflects running recording'` test, still inside `group('RecordingController', ...)`:

```dart
    // ── Stop ───────────────────────────────────────────────────────────────

    test('stop() sends SIGINT and sets isRecording to false', () async {
      await ctrl.start('emulator-5554');
      await ctrl.stop(savePath: '/tmp/rec_test.mp4');

      expect(ctrl.isRecording, isFalse);
      expect(adb._lastProcess!.wasKilled, isTrue);
    });

    test('stop() calls pullFile then removeFile with matching paths', () async {
      await ctrl.start('emulator-5554');
      await ctrl.stop(savePath: '/tmp/rec_test.mp4');

      expect(adb.pullCalls, hasLength(1));
      expect(adb.removeCalls, hasLength(1));
      expect(adb.pullCalls.first.$2, adb.removeCalls.first.$2);
    });

    test('stop() returns the requested local path', () async {
      await ctrl.start('emulator-5554');
      final localPath = await ctrl.stop(savePath: '/tmp/rec_out.mp4');

      expect(localPath, '/tmp/rec_out.mp4');
    });

    test('stop() uses default ~/Downloads path when savePath is null', () async {
      await ctrl.start('emulator-5554');
      final localPath = await ctrl.stop();

      expect(localPath, contains('Downloads/scrcpy_records/rec_'));
      expect(localPath, endsWith('.mp4'));
    });
```

- [ ] **Step 2: Run — expect all 9 tests to pass**

```bash
cd scrcpy_mcp && flutter test test/recording_controller_test.dart
```

Expected: 9 tests pass.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_mcp/test/recording_controller_test.dart
git commit -m "test(scrcpy_mcp): add RecordingController stop() happy-path tests"
```

---

## Task 4: RecordingController — error cases + unexpected exit (TDD)

**Files:**
- Modify: `scrcpy_mcp/test/recording_controller_test.dart`

- [ ] **Step 1: Append remaining tests inside the same `group`**

```dart
    // ── Error cases ────────────────────────────────────────────────────────

    test('start() while recording throws StateError', () async {
      await ctrl.start('emulator-5554');

      expect(() => ctrl.start('emulator-5554'), throwsStateError);
    });

    test('pullFile failure rethrows and does NOT call removeFile', () async {
      adb.pullError = Exception('adb pull failed');
      await ctrl.start('emulator-5554');

      await expectLater(
        () => ctrl.stop(savePath: '/tmp/rec_test.mp4'),
        throwsException,
      );
      expect(adb.removeCalls, isEmpty);
    });

    // ── Unexpected exit ────────────────────────────────────────────────────

    test('unexpected process exit resets state to idle', () async {
      await ctrl.start('emulator-5554');
      expect(ctrl.isRecording, isTrue);

      adb.simulateUnexpectedExit(1);
      await Future<void>.delayed(Duration.zero); // let then() callback run

      expect(ctrl.isRecording, isFalse);
    });

    // ── Status JSON ────────────────────────────────────────────────────────

    test('status.toJson() when idle omits optional keys', () {
      final json = ctrl.status.toJson();

      expect(json['is_recording'], isFalse);
      expect(json.containsKey('device_id'), isFalse);
      expect(json.containsKey('start_time'), isFalse);
      expect(json.containsKey('remote_path'), isFalse);
    });

    test('status.toJson() while recording includes all keys', () async {
      await ctrl.start('emulator-5554');
      final json = ctrl.status.toJson();

      expect(json['is_recording'], isTrue);
      expect(json['device_id'], 'emulator-5554');
      expect(json.containsKey('start_time'), isTrue);
      expect(json.containsKey('remote_path'), isTrue);
    });
```

- [ ] **Step 2: Run — expect all 14 tests to pass**

```bash
cd scrcpy_mcp && flutter test test/recording_controller_test.dart
```

Expected: 14 tests pass.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_mcp/test/recording_controller_test.dart
git commit -m "test(scrcpy_mcp): add RecordingController error and unexpected-exit tests"
```

---

## Task 5: ScrcpyMcpAdb implements RecordingAdb

**Files:**
- Modify: `scrcpy_mcp/lib/src/scrcpy_mcp_adapters.dart`

- [ ] **Step 1: Replace full file content**

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_logger/autoglm_logger.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

import 'recording_adb.dart';

/// Wraps [dart:io Process] to expose only what [RecordingController] needs.
class _RealProcess implements RecordingProcess {
  _RealProcess(this._process);
  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}

/// Bridges the MCP package's ADB client to the scrcpy package boundary.
class ScrcpyMcpAdb implements ScrcpyAdb, RecordingAdb {
  const ScrcpyMcpAdb(this._client);

  final AdbClient _client;

  @override
  String get adbPath => _client.adbPath;

  @override
  Future<List<String>> getDevices() => _client.getDevices();

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _client.shell(arguments, deviceId: deviceId, timeout: timeout);
  }

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) {
    return _client.forward(
      local,
      remote,
      deviceId: deviceId,
      noRebind: noRebind,
    );
  }

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) {
    return _client.forwardRemove(local, deviceId: deviceId);
  }

  @override
  Future<void> push(String localPath, String remotePath, {String? deviceId}) {
    return _client.push(localPath, remotePath, deviceId: deviceId);
  }

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async {
    final result = await Process.run(
      adbPath,
      ['-s', deviceId, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) {
      throw Exception(
        'screencap failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
    return Uint8List.fromList(result.stdout as List<int>);
  }

  // ── RecordingAdb ──────────────────────────────────────────────────────────

  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    final process = await Process.start(adbPath, [
      '-s', deviceId, 'shell', 'screenrecord',
      '--bit-rate', '$bitrate',
      '--time-limit', '$maxTime',
      remotePath,
    ]);
    // Drain to prevent pipe backpressure from blocking the recording process.
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    return _RealProcess(process);
  }

  @override
  Future<void> pullFile(
    String deviceId,
    String remotePath,
    String localPath,
  ) async {
    final result = await Process.run(
      adbPath,
      ['-s', deviceId, 'pull', remotePath, localPath],
    );
    if (result.exitCode != 0) {
      throw Exception(
        'adb pull failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
  }

  @override
  Future<void> removeFile(String deviceId, String remotePath) async {
    await Process.run(
      adbPath,
      ['-s', deviceId, 'shell', 'rm', '-f', remotePath],
    );
  }
}

/// Bridges MCP scrcpy logs to the shared application logger.
class ScrcpyMcpLogger implements ScrcpyLogger {
  const ScrcpyMcpLogger();

  @override
  void debug(String message) => appLogger.d(message);

  @override
  void info(String message) => appLogger.i(message);

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    appLogger.w(message, error, stack);
  }

  @override
  void error(String message, [Object? error, StackTrace? stack]) {
    appLogger.e(message, error, stack);
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd scrcpy_mcp && dart analyze lib/src/scrcpy_mcp_adapters.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_mcp/lib/src/scrcpy_mcp_adapters.dart
git commit -m "feat(scrcpy_mcp): ScrcpyMcpAdb implements RecordingAdb via adb screenrecord"
```

---

## Task 6: Wire recording into ScrcpyMcpServer + McpHttpServer

**Files:**
- Modify: `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`
- Modify: `scrcpy_mcp/lib/src/mcp_http_server.dart`

- [ ] **Step 1: Replace full `scrcpy_mcp_server.dart`**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

import 'recording_adb.dart';
import 'recording_controller.dart';

/// MCP server exposing scrcpy operations via the Model Context Protocol.
class ScrcpyMcpServer {
  ScrcpyMcpServer({
    required ScrcpySession session,
    required ScrcpyAdb adb,
    RecordingAdb? recordingAdb,
  })  : _session = session,
        _adb = adb {
    if (recordingAdb != null) {
      _recordingController = RecordingController(recordingAdb);
    }
    _mcpServer = McpServer(
      const Implementation(name: 'scrcpy-mcp', version: '0.2.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
          resources: ServerCapabilitiesResources(),
          prompts: ServerCapabilitiesPrompts(),
        ),
      ),
    );
    _registerAll();
  }

  final ScrcpySession _session;
  final ScrcpyAdb _adb;
  late final McpServer _mcpServer;
  RecordingController? _recordingController;
  String? _connectedDeviceId;

  McpServer get mcpServer => _mcpServer;

  void _registerAll() {
    _registerTools();
    _registerResources();
    _registerPrompts();
  }

  void _registerTools() {
    _mcpServer
      ..registerTool(
        'list_devices',
        description: 'List connected Android devices.',
        inputSchema: JsonSchema.object(properties: {}),
        callback: _listDevices,
      )
      ..registerTool(
        'start_mirroring',
        description: 'Start screen mirroring for a device.',
        inputSchema: JsonSchema.object(
          properties: {
            'device_id': JsonSchema.string(
              description: 'The Android device serial',
            ),
          },
          required: ['device_id'],
        ),
        callback: _startMirroring,
      )
      ..registerTool(
        'stop_mirroring',
        description: 'Stop the active mirroring session.',
        inputSchema: JsonSchema.object(properties: {}),
        callback: _stopMirroring,
      )
      ..registerTool(
        'inject_key',
        description: 'Send a key event to the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'keycode': JsonSchema.integer(
              description: 'Android KeyEvent keycode',
            ),
            'action': JsonSchema.integer(
              description: 'Key action: 0=down, 1=up (default: 0)',
            ),
          },
          required: ['keycode'],
        ),
        callback: _injectKey,
      )
      ..registerTool(
        'inject_touch',
        description: 'Send a touch event to the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'x': JsonSchema.integer(description: 'X coordinate'),
            'y': JsonSchema.integer(description: 'Y coordinate'),
            'width': JsonSchema.integer(description: 'Screen width'),
            'height': JsonSchema.integer(description: 'Screen height'),
            'action': JsonSchema.integer(
              description: 'Touch action: 0=down, 1=up, 2=move (default: 0)',
            ),
          },
          required: ['x', 'y', 'width', 'height'],
        ),
        callback: _injectTouch,
      )
      ..registerTool(
        'inject_text',
        description: 'Input text on the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'text': JsonSchema.string(description: 'Text to input'),
          },
          required: ['text'],
        ),
        callback: _injectText,
      )
      ..registerTool(
        'inject_scroll',
        description: 'Send a scroll event to the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'x': JsonSchema.integer(description: 'X coordinate'),
            'y': JsonSchema.integer(description: 'Y coordinate'),
            'width': JsonSchema.integer(description: 'Screen width'),
            'height': JsonSchema.integer(description: 'Screen height'),
            'hScroll': JsonSchema.integer(
              description: 'Horizontal scroll amount',
            ),
            'vScroll': JsonSchema.integer(
              description: 'Vertical scroll amount',
            ),
          },
          required: ['x', 'y', 'width', 'height', 'hScroll', 'vScroll'],
        ),
        callback: _injectScroll,
      )
      ..registerTool(
        'take_screenshot',
        description:
            'Capture the current screen of the device as a PNG image.',
        inputSchema: JsonSchema.object(
          properties: {
            'device_id': JsonSchema.string(
              description:
                  'Device serial (optional, uses connected device if omitted)',
            ),
          },
        ),
        callback: _takeScreenshot,
      );

    if (_recordingController != null) {
      _mcpServer
        ..registerTool(
          'start_recording',
          description: 'Start screen recording on the active mirroring device '
              '(max 180 s, Android limit). '
              'Protected content may record as black.',
          inputSchema: JsonSchema.object(
            properties: {
              'bitrate': JsonSchema.integer(
                description: 'Video bitrate in bps (default: 4000000)',
              ),
              'max_time': JsonSchema.integer(
                description:
                    'Max duration in seconds, Android limit is 180 '
                    '(default: 180)',
              ),
            },
          ),
          callback: _startRecording,
        )
        ..registerTool(
          'stop_recording',
          description:
              'Stop the active screen recording and save to local disk.',
          inputSchema: JsonSchema.object(
            properties: {
              'save_path': JsonSchema.string(
                description: 'Local file path '
                    '(default: ~/Downloads/scrcpy_records/rec_<timestamp>.mp4)',
              ),
            },
          ),
          callback: _stopRecording,
        );
    }
  }

  void _registerResources() {
    _mcpServer
      ..registerResource(
        'Connected Devices',
        'device://list',
        (
          description: 'List of currently connected Android devices.',
          mimeType: 'application/json',
        ),
        _readDeviceList,
      )
      ..registerResource(
        'Mirroring Status',
        'mirroring://status',
        (
          description: 'Current mirroring session status.',
          mimeType: 'application/json',
        ),
        _readMirroringStatus,
      );

    if (_recordingController != null) {
      _mcpServer.registerResource(
        'Recording Status',
        'recording://status',
        (
          description: 'Current screen recording state.',
          mimeType: 'application/json',
        ),
        _readRecordingStatus,
      );
    }
  }

  void _registerPrompts() {
    _mcpServer
      ..registerPrompt(
        'control_device',
        description: 'Assist with Android device control via scrcpy.',
        argsSchema: {
          'device_id': const PromptArgumentDefinition(
            description: 'The device to control (optional if only one device)',
          ),
        },
        callback: _getControlDevicePrompt,
      )
      ..registerPrompt(
        'troubleshoot',
        description: 'Help diagnose and fix device connection issues.',
        argsSchema: {
          'issue': const PromptArgumentDefinition(
            description: 'Description of the issue encountered',
          ),
        },
        callback: _getTroubleshootPrompt,
      );
  }

  // ── Tool implementations ──────────────────────────────────────────────────

  Future<CallToolResult> _listDevices(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final devices = await _adb.getDevices();
    return CallToolResult.fromContent(
      [TextContent(text: jsonEncode(devices))],
    );
  }

  Future<CallToolResult> _startMirroring(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceId = args['device_id'] as String;
    try {
      await _session.start(deviceId);
      _connectedDeviceId = deviceId;
      return CallToolResult.fromContent([
        TextContent(
          text: jsonEncode({
            'status': 'mirroring',
            'device_id': deviceId,
            'proxy_url': _session.proxyUrl,
            'player_url': _session.playerUrl,
          }),
        ),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed to start mirroring: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _stopMirroring(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) {
      return CallToolResult.fromContent(
        [const TextContent(text: 'No active mirroring session.')],
      );
    }
    await _session.stop();
    _connectedDeviceId = null;
    return CallToolResult.fromContent(
      [const TextContent(text: 'Mirroring stopped.')],
    );
  }

  Future<CallToolResult> _injectKey(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) {
      return const CallToolResult(
        content: [TextContent(text: 'No active mirroring session.')],
        isError: true,
      );
    }
    final keycode = args['keycode'] as int;
    final action = args['action'] as int? ?? ScrcpyAction.down;
    _session.sendControlMessage(
      ScrcpyInjectKeyMessage(action: action, keycode: keycode),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Key event sent: keycode=$keycode, action=$action'),
    ]);
  }

  Future<CallToolResult> _injectTouch(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) {
      return const CallToolResult(
        content: [TextContent(text: 'No active mirroring session.')],
        isError: true,
      );
    }
    final x = args['x'] as int;
    final y = args['y'] as int;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final action = args['action'] as int? ?? ScrcpyAction.down;
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: action,
        pointerId: 0,
        x: x,
        y: y,
        width: width,
        height: height,
      ),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Touch event sent: ($x, $y) action=$action'),
    ]);
  }

  Future<CallToolResult> _injectText(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) {
      return const CallToolResult(
        content: [TextContent(text: 'No active mirroring session.')],
        isError: true,
      );
    }
    final text = args['text'] as String;
    _session.injectText(text);
    return CallToolResult.fromContent(
      [TextContent(text: 'Text sent: "$text"')],
    );
  }

  Future<CallToolResult> _injectScroll(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) {
      return const CallToolResult(
        content: [TextContent(text: 'No active mirroring session.')],
        isError: true,
      );
    }
    final x = args['x'] as int;
    final y = args['y'] as int;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final hScroll = args['hScroll'] as int;
    final vScroll = args['vScroll'] as int;
    _session.sendControlMessage(
      ScrcpyInjectScrollMessage(
        x: x,
        y: y,
        width: width,
        height: height,
        hScroll: hScroll,
        vScroll: vScroll,
      ),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Scroll event sent: ($x, $y) h=$hScroll v=$vScroll'),
    ]);
  }

  Future<CallToolResult> _takeScreenshot(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceIdArg = args['device_id'] as String?;
    final deviceId = deviceIdArg ?? _connectedDeviceId;
    if (deviceId != null) {
      return _doScreenshot(deviceId);
    }
    final devices = await _adb.getDevices();
    if (devices.isEmpty) {
      return const CallToolResult(
        content: [TextContent(text: 'No devices connected.')],
        isError: true,
      );
    }
    return _doScreenshot(devices.first);
  }

  Future<CallToolResult> _doScreenshot(String deviceId) async {
    try {
      final pngBytes = await _adb.takeScreenshot(deviceId);
      return CallToolResult.fromContent([
        ImageContent(data: base64Encode(pngBytes), mimeType: 'image/png'),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Screenshot failed: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _startRecording(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) {
      return const CallToolResult(
        content: [
          TextContent(
            text: 'No active mirroring session. Call start_mirroring first.',
          ),
        ],
        isError: true,
      );
    }
    if (_recordingController!.isRecording) {
      final s = _recordingController!.status;
      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'error': 'Already recording',
              'device_id': s.deviceId,
              'start_time': s.startTime?.toUtc().toIso8601String(),
            }),
          ),
        ],
        isError: true,
      );
    }
    final deviceId = _connectedDeviceId!;
    final bitrate = args['bitrate'] as int? ?? 4000000;
    final maxTime = args['max_time'] as int? ?? 180;
    try {
      final remotePath = await _recordingController!.start(
        deviceId,
        bitrate: bitrate,
        maxTime: maxTime,
      );
      return CallToolResult.fromContent([
        TextContent(
          text: jsonEncode({
            'status': 'recording',
            'path_on_device': remotePath,
          }),
        ),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed to start recording: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _stopRecording(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_recordingController!.isRecording) {
      return CallToolResult.fromContent(
        [const TextContent(text: 'No active recording.')],
      );
    }
    final savePath = args['save_path'] as String?;
    try {
      final localPath = await _recordingController!.stop(savePath: savePath);
      final sizeBytes = await File(localPath).length();
      return CallToolResult.fromContent([
        TextContent(
          text: jsonEncode({
            'status': 'finished',
            'local_path': localPath,
            'size_bytes': sizeBytes,
          }),
        ),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed to stop recording: $e')],
        isError: true,
      );
    }
  }

  // ── Resource implementations ──────────────────────────────────────────────

  Future<ReadResourceResult> _readDeviceList(
    Uri uri,
    RequestHandlerExtra extra,
  ) async {
    final devices = await _adb.getDevices();
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: jsonEncode(devices),
        ),
      ],
    );
  }

  Future<ReadResourceResult> _readMirroringStatus(
    Uri uri,
    RequestHandlerExtra extra,
  ) async {
    final status = <String, dynamic>{
      'active': _session.isConnected,
      if (_connectedDeviceId != null) 'device_id': _connectedDeviceId,
    };
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: jsonEncode(status),
        ),
      ],
    );
  }

  Future<ReadResourceResult> _readRecordingStatus(
    Uri uri,
    RequestHandlerExtra extra,
  ) async {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: jsonEncode(_recordingController!.status.toJson()),
        ),
      ],
    );
  }

  // ── Prompt implementations ────────────────────────────────────────────────

  Future<GetPromptResult> _getControlDevicePrompt(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    final deviceId = args?['device_id'] as String?;
    final devices = await _adb.getDevices();
    final deviceInfo = deviceId != null
        ? 'Target device: $deviceId'
        : 'Available devices: ${devices.join(", ")}';
    final recordingLine = _recordingController != null
        ? '- start_recording, stop_recording '
            '(max 180 s; requires active mirroring)\n'
        : '';

    return GetPromptResult(
      description: 'Device control assistant',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'You are an Android device control assistant.\n\n'
                '$deviceInfo\n\n'
                'Available tools:\n'
                '- list_devices, start_mirroring, stop_mirroring\n'
                '- inject_key (Home=3, Back=4, AppSwitch=187)\n'
                '- inject_touch, inject_text, inject_scroll\n'
                '- take_screenshot\n'
                '$recordingLine\n'
                'Help the user control their Android device.',
          ),
        ),
      ],
    );
  }

  Future<GetPromptResult> _getTroubleshootPrompt(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    final issue = args?['issue'] as String?;
    final devices = await _adb.getDevices();

    return GetPromptResult(
      description: 'Device troubleshooting assistant',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'You are an Android device troubleshooting assistant.\n\n'
                'Connected devices: '
                '${devices.isEmpty ? "none" : devices.join(", ")}\n'
                '${issue != null ? "Reported issue: $issue\n" : ""}\n'
                'Common issues:\n'
                '1. No devices: Check USB connection, enable USB debugging\n'
                '2. Connection refused: Run adb kill-server\n'
                '3. Mirroring fails: Check scrcpy server version\n'
                '4. Black screen: Device may be locked\n'
                '5. Black recording: Protected content (payment/login screens) '
                'records as black — Android security restriction.\n\n'
                'Help the user diagnose and resolve their issue.',
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Replace full `mcp_http_server.dart`**

```dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/src/recording_adb.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class McpHttpServer {
  StreamableMcpServer? _server;
  int? _port;

  String? get serverUrl => _port != null ? 'http://localhost:$_port/mcp' : null;

  Future<void> start({
    required int port,
    required ScrcpySession session,
    required ScrcpyAdb adb,
    RecordingAdb? recordingAdb,
  }) async {
    _server = StreamableMcpServer(
      serverFactory: (_) => ScrcpyMcpServer(
        session: session,
        adb: adb,
        recordingAdb: recordingAdb,
      ).mcpServer,
      port: port,
      enableDnsRebindingProtection: false,
    );
    await _server!.start();
    _port = port;
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    _port = null;
  }
}
```

- [ ] **Step 3: Run existing tests — expect all to still pass**

```bash
cd scrcpy_mcp && flutter test
```

Expected: all existing tests pass (existing `_TestEnv` passes no `recordingAdb`, so tool count stays at 8).

- [ ] **Step 4: Commit**

```bash
git add scrcpy_mcp/lib/src/scrcpy_mcp_server.dart \
        scrcpy_mcp/lib/src/mcp_http_server.dart
git commit -m "feat(scrcpy_mcp): add start_recording/stop_recording tools and recording://status resource"
```

---

## Task 7: Server-level recording tests + wire bin entry point

**Files:**
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`
- Modify: `scrcpy_mcp/bin/scrcpy_mcp.dart`

- [ ] **Step 1: Add `recording_adb.dart` import to the test file**

After the last existing import in `scrcpy_mcp_server_test.dart`, add:

```dart
import 'package:scrcpy_mcp/src/recording_adb.dart';
```

- [ ] **Step 2: Add `_MockRecordingAdb`, `_FakeRecordingProcess`, and `_RecordingTestEnv` after the existing `_TestEnv` class**

```dart
// ---------------------------------------------------------------------------
// Recording mocks + env
// ---------------------------------------------------------------------------

class _MockRecordingAdb implements RecordingAdb {
  _FakeRecordingProcess? _lastProcess;

  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    _lastProcess = _FakeRecordingProcess();
    return _lastProcess!;
  }

  @override
  Future<void> pullFile(
    String deviceId,
    String remotePath,
    String localPath,
  ) async {
    // Write a minimal file so File(localPath).length() succeeds in _stopRecording.
    await File(localPath).writeAsBytes([0]);
  }

  @override
  Future<void> removeFile(String deviceId, String remotePath) async {}
}

class _FakeRecordingProcess implements RecordingProcess {
  final _completer = Completer<int>();

  @override
  Future<int> get exitCode => _completer.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_completer.isCompleted) _completer.complete(0);
    return true;
  }
}

class _RecordingTestEnv {
  _RecordingTestEnv({List<String>? devices})
      : adb = MockAdb(devices: devices ?? ['device1']),
        recordingAdb = _MockRecordingAdb(),
        viewController = MockScrcpyViewController() {
    server = ScrcpyMcpServer(
      session: viewController,
      adb: adb,
      recordingAdb: recordingAdb,
    );
  }

  final MockAdb adb;
  final _MockRecordingAdb recordingAdb;
  final MockScrcpyViewController viewController;
  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async {
    final serverToClient = StreamController<List<int>>();
    final clientToServer = StreamController<List<int>>();

    final serverTransport = IOStreamTransport(
      stream: clientToServer.stream,
      sink: serverToClient.sink,
    );
    final clientTransport = IOStreamTransport(
      stream: serverToClient.stream,
      sink: clientToServer.sink,
    );

    await server.mcpServer.connect(serverTransport);

    client = McpClient(
      const Implementation(name: 'test-client', version: '0.0.1'),
      options: const McpClientOptions(capabilities: ClientCapabilities()),
    );
    await client.connect(clientTransport);

    addTearDown(() async {
      await serverToClient.close();
      await clientToServer.close();
      viewController.dispose();
    });
  }
}
```

- [ ] **Step 3: Add the recording test group at the end of `main()`**

```dart
  group('ScrcpyMcpServer — recording', () {
    test('advertises start_recording and stop_recording when enabled',
        () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final tools = await env.client.listTools();
      final names = tools.tools.map((t) => t.name).toSet();

      expect(names, contains('start_recording'));
      expect(names, contains('stop_recording'));
    });

    test('advertises recording://status resource when enabled', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final resources = await env.client.listResources();
      final uris = resources.resources.map((r) => r.uri).toSet();

      expect(uris, contains('recording://status'));
    });

    test('start_recording without active mirroring returns error', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      expect(result.isError, isTrue);
      expect(_text(result), contains('No active mirroring session'));
    });

    test('start_recording while already recording returns error', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      await env.client.callTool(
        const CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': 'device1'},
        ),
      );
      await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      final result = await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      expect(result.isError, isTrue);
      expect(_text(result), contains('Already recording'));
    });

    test('stop_recording when not recording returns friendly message',
        () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'stop_recording'),
      );

      expect(result.isError, isFalse);
      expect(_text(result), contains('No active recording'));
    });

    test('recording://status is idle when not recording', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final result = await env.client.readResource(
        const ReadResourceRequest(uri: 'recording://status'),
      );

      final json =
          jsonDecode(_resourceText(result)) as Map<String, dynamic>;
      expect(json['is_recording'], isFalse);
    });

    test('recording://status reflects active recording', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      await env.client.callTool(
        const CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': 'device1'},
        ),
      );
      await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      final result = await env.client.readResource(
        const ReadResourceRequest(uri: 'recording://status'),
      );
      final json =
          jsonDecode(_resourceText(result)) as Map<String, dynamic>;

      expect(json['is_recording'], isTrue);
      expect(json['device_id'], 'device1');
    });
  });
```

- [ ] **Step 4: Run all tests — expect all to pass**

```bash
cd scrcpy_mcp && flutter test
```

Expected: all existing tests pass + 7 new recording tests pass.

- [ ] **Step 5: Update `bin/scrcpy_mcp.dart`**

Replace full file:

```dart
#!/usr/bin/env dart

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

void main(List<String> args) async {
  final adbPath = args.isNotEmpty ? args[0] : 'adb';
  final adb = AdbClient(adbPath: adbPath);
  final scrcpyAdb = ScrcpyMcpAdb(adb);

  final viewController = ScrcpyViewController(adb: scrcpyAdb);
  final server = ScrcpyMcpServer(
    session: viewController,
    adb: scrcpyAdb,
    recordingAdb: scrcpyAdb,
  );

  final transport = StdioServerTransport();
  await server.mcpServer.connect(transport);
}
```

- [ ] **Step 6: Final analysis check**

```bash
cd scrcpy_mcp && dart analyze
```

Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add scrcpy_mcp/test/scrcpy_mcp_server_test.dart \
        scrcpy_mcp/bin/scrcpy_mcp.dart
git commit -m "feat(scrcpy_mcp): wire recording into bin entry point, add server-level recording tests"
```

---

## Spec Coverage Check

| Requirement | Task |
|-------------|------|
| `start_recording` tool | Task 6 |
| `stop_recording` tool | Task 6 |
| `recording://status` resource | Task 6 |
| `RecordingAdb` interface | Task 1 |
| `RecordingProcess` narrow interface (testability) | Task 1 |
| `RecordingStatus.toJson()` | Task 1 |
| `RecordingController` state machine | Tasks 2–4 |
| SIGINT for graceful stop (MP4 header preserved) | Task 2 (`process.kill(ProcessSignal.sigint)`) |
| pullFile before removeFile ordering | Task 3 |
| pull failure → device file preserved | Task 4 |
| Unexpected exit → state reset to idle | Task 4 |
| Default save path `~/Downloads/scrcpy_records/` | Task 3 |
| Timestamp-based file naming | Task 2 |
| Error: no mirroring → start_recording fails | Tasks 4, 7 |
| Error: already recording → start_recording fails | Tasks 4, 7 |
| `ScrcpyMcpAdb` implements `RecordingAdb` | Task 5 |
| stdout/stderr drain (prevent backpressure) | Task 5 |
| `McpHttpServer` forwards optional `recordingAdb` | Task 6 |
| `bin/scrcpy_mcp.dart` wired | Task 7 |
| `control_device` prompt updated | Task 6 |
| `troubleshoot` prompt updated | Task 6 |
| No changes to `scrcpy_view` / `scrcpy_app` | All tasks |
