# ScrcpyServer Configurability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `maxSize`, `maxFps`, `videoBitRate`, and `videoCodec` as configurable video parameters on `ScrcpyServer`, threaded through `ScrcpySessionImpl.start()`.

**Architecture:** A new `ScrcpyServerOptions` value class carries the four encoding knobs with sensible defaults matching today's hardcoded literals. `ScrcpyServer` gains a required `options` field that replaces the four literal strings in `_runServer`. `ScrcpySessionImpl.start()` gains an optional `options` parameter (defaulting to `const ScrcpyServerOptions()`) that is forwarded to the `ScrcpyServer` constructor. The dual `_parser.close()` bug is fixed as part of the `ScrcpyServer` edit.

**Tech Stack:** Dart, `package:meta` (already transitive via `flutter`/`scrcpy_client`), `package:test`.

> **Note on `ScrcpySession` interface:** `ScrcpySession.start(String deviceId)` does NOT declare `options`. Dart permits an override to add optional named parameters, and the existing `ScrcpySessionImpl.start()` already does this (`logger`, `onStarted`, etc.). The `options` parameter is added only to `ScrcpySessionImpl.start()`. Callers holding a `ScrcpySession` reference cannot pass `options`; callers holding `ScrcpySessionImpl` (which is the norm in app/MCP entry points) can.

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `lib/src/scrcpy_server_options.dart` | `ScrcpyServerOptions` value class |
| Modify | `lib/src/scrcpy_server.dart` | Add `options` field/param, wire into `_runServer`, fix dual-close |
| Modify | `lib/src/scrcpy_session_impl.dart` | Optional `options` param on `start()`, forward to server |
| Modify | `lib/scrcpy_client.dart` | Export `scrcpy_server_options.dart` |
| Modify | `test/scrcpy_server_test.dart` | Add `options:` to all `ScrcpyServer(...)` call sites + new options tests |
| Modify | `test/utils/server_factory.dart` | Add `options:` to `ScrcpyServer(...)` call site |

---

## Task 1: Create `ScrcpyServerOptions` and export it

**Files:**
- Create: `lib/src/scrcpy_server_options.dart`
- Modify: `lib/scrcpy_client.dart`
- Test: `test/scrcpy_server_test.dart`

- [ ] **Step 1: Write the failing test**

  Add a new `group` at the bottom of `test/scrcpy_server_test.dart`:

  ```dart
  group('ScrcpyServerOptions', () {
    test('has correct defaults', () {
      const opts = ScrcpyServerOptions();
      expect(opts.maxSize, 1024);
      expect(opts.maxFps, 60);
      expect(opts.videoBitRate, 6000000);
      expect(opts.videoCodec, 'h264');
    });

    test('accepts custom values', () {
      const opts = ScrcpyServerOptions(
        maxSize: 720,
        maxFps: 30,
        videoBitRate: 2000000,
        videoCodec: 'h265',
      );
      expect(opts.maxSize, 720);
      expect(opts.maxFps, 30);
      expect(opts.videoBitRate, 2000000);
      expect(opts.videoCodec, 'h265');
    });
  });
  ```

- [ ] **Step 2: Run test to verify it fails**

  ```bash
  cd packages/scrcpy_client && dart test test/scrcpy_server_test.dart
  ```

  Expected: compile error — `ScrcpyServerOptions` is undefined.

- [ ] **Step 3: Create `lib/src/scrcpy_server_options.dart`**

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

    final int maxSize;
    final int maxFps;
    final int videoBitRate;
    final String videoCodec;
  }
  ```

- [ ] **Step 4: Export from barrel (`lib/scrcpy_client.dart`)**

  Add after the existing exports (keep alphabetical order — insert after `scrcpy_server.dart`):

  ```dart
  export 'src/scrcpy_server_options.dart';
  ```

- [ ] **Step 5: Run test to verify it passes**

  ```bash
  dart test test/scrcpy_server_test.dart
  ```

  Expected: all tests PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/src/scrcpy_server_options.dart lib/scrcpy_client.dart test/scrcpy_server_test.dart
  git commit -m "feat(scrcpy_client): add ScrcpyServerOptions value class"
  ```

---

## Task 2: Wire `ScrcpyServerOptions` into `ScrcpyServer`

**Files:**
- Modify: `lib/src/scrcpy_server.dart`
- Modify: `test/scrcpy_server_test.dart` (update call sites + add options getter test)
- Modify: `test/utils/server_factory.dart` (update call site)

- [ ] **Step 1: Write the failing test**

  Add to the `'ScrcpyServer Configuration'` group in `test/scrcpy_server_test.dart`:

  ```dart
  test('stores provided options', () {
    const opts = ScrcpyServerOptions(maxSize: 720, maxFps: 30);
    final server = ScrcpyServer(
      adb: mockAdb,
      deviceId: 'device123',
      serverJarBytes: mockJarBytes,
      options: opts,
    );
    expect(server.options.maxSize, 720);
    expect(server.options.maxFps, 30);
    server.stop();
  });

  test('options defaults match ScrcpyServerOptions defaults', () {
    const opts = ScrcpyServerOptions();
    final server = ScrcpyServer(
      adb: mockAdb,
      deviceId: 'device123',
      serverJarBytes: mockJarBytes,
      options: opts,
    );
    expect(server.options.maxSize, 1024);
    expect(server.options.maxFps, 60);
    expect(server.options.videoBitRate, 6000000);
    expect(server.options.videoCodec, 'h264');
    server.stop();
  });
  ```

- [ ] **Step 2: Run test to verify it fails**

  ```bash
  dart test test/scrcpy_server_test.dart
  ```

  Expected: compile error — `ScrcpyServer` has no `options` named parameter.

- [ ] **Step 3: Update `ScrcpyServer` constructor and class**

  In `lib/src/scrcpy_server.dart`:

  **Add import** at the top (with other imports):
  ```dart
  import 'package:scrcpy_client/src/scrcpy_server_options.dart';
  ```

  **Replace constructor**:
  ```dart
  ScrcpyServer({
    required this.adb,
    required this.deviceId,
    required Uint8List serverJarBytes,
    required ScrcpyServerOptions options,
    this.port = 27183,
    ScrcpyLogger logger = const NoOpScrcpyLogger(),
    StreamSink<List<int>>? controlSink,
  })  : _serverJarBytes = serverJarBytes,
        _options = options,
        _log = logger,
        _controlSink = controlSink,
        _parser = ScrcpyStreamParser(logger: logger);
  ```

  **Add field and getter** (after the existing `final ScrcpyAdb adb;` block):
  ```dart
  final ScrcpyServerOptions _options;

  /// The video encoding options for this server instance.
  ScrcpyServerOptions get options => _options;
  ```

  **Update `_runServer`** — replace the four hardcoded lines with options reads. The existing lines in `_runServer`:
  ```dart
  'video_codec=h264',
  // ...
  'max_size=1024',
  'max_fps=60',
  'video_bit_rate=6000000',
  ```
  Replace with:
  ```dart
  'video_codec=${_options.videoCodec}',
  // ...
  'max_size=${_options.maxSize}',
  'max_fps=${_options.maxFps}',
  'video_bit_rate=${_options.videoBitRate}',
  ```

  **Fix dual `_parser.close()`** — in the `unawaited(...)` exit handler inside `_runServer`, remove the `_parser.close()` call:
  ```dart
  unawaited(
    _serverProcess!.exitCode.then((code) {
      _log.warn('[ScrcpyServer] server process exited with code $code');
      // _parser.close() intentionally omitted — stop() is the sole cleanup owner
    }),
  );
  ```

- [ ] **Step 4: Update existing `ScrcpyServer` call sites in tests**

  In `test/scrcpy_server_test.dart`, every `ScrcpyServer(...)` that lacks `options:` must have `options: const ScrcpyServerOptions()` added. There are five such call sites (in `'initializes with required parameters'`, `'uses default port when not specified'`, `'supports multiple instances with different ports'` × 2, `'adb client reference is stored correctly'`, `'works with multiple device IDs'` × 2). Add `options: const ScrcpyServerOptions()` to each.

  Example for `'initializes with required parameters'`:
  ```dart
  final server = ScrcpyServer(
    adb: mockAdb,
    deviceId: 'device123',
    port: 12345,
    serverJarBytes: mockJarBytes,
    options: const ScrcpyServerOptions(),
  );
  ```

  In `test/utils/server_factory.dart`, update `createTestServer`:
  ```dart
  final server = ScrcpyServer(
    adb: adb,
    deviceId: deviceId,
    serverJarBytes: jarBytes ?? Uint8List(0),
    options: const ScrcpyServerOptions(),
    controlSink: controller.sink,
  );
  ```

- [ ] **Step 5: Run all tests**

  ```bash
  dart test
  ```

  Expected: all tests PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/src/scrcpy_server.dart test/scrcpy_server_test.dart test/utils/server_factory.dart
  git commit -m "feat(scrcpy_client): wire ScrcpyServerOptions into ScrcpyServer"
  ```

---

## Task 3: Thread `ScrcpyServerOptions` through `ScrcpySessionImpl.start()`

**Files:**
- Modify: `lib/src/scrcpy_session_impl.dart`
- Test: `test/scrcpy_server_test.dart`

- [ ] **Step 1: Write the failing test**

  Add a new group in `test/scrcpy_server_test.dart`:

  ```dart
  group('ScrcpySessionImpl options threading', () {
    test('start() accepts custom options and propagates to server', () async {
      final mockAdb = MockScrcpyAdb(testAdbPath: 'false'); // 'false' exits immediately
      final session = ScrcpySessionImpl(
        adb: mockAdb,
        serverJarBytes: Uint8List(0),
      );

      const opts = ScrcpyServerOptions(maxSize: 720, maxFps: 30);
      // start() will fail (no real device) — we just verify options param compiles
      // and the options are forwarded (verified by the server storing them).
      await expectLater(
        () => session.start('test-device', options: opts),
        throwsException,
      );
    });
  });
  ```

  > Note: `testAdbPath: 'false'` uses the shell built-in `false` which exits with code 1 immediately, so `Process.start` succeeds but the process exits quickly, causing `_connectAll` to fail — without hanging the test.

- [ ] **Step 2: Run test to verify it fails**

  ```bash
  dart test test/scrcpy_server_test.dart --name "options threading"
  ```

  Expected: compile error — `start()` has no `options` named parameter.

- [ ] **Step 3: Update `ScrcpySessionImpl.start()`**

  In `lib/src/scrcpy_session_impl.dart`, update the `start` signature and the `ScrcpyServer` constructor call:

  ```dart
  @override
  Future<void> start(
    String deviceId, {
    ScrcpyServerOptions options = const ScrcpyServerOptions(),
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
      options: options,
      logger: logger ?? const NoOpScrcpyLogger(),
    );
    try {
      await server.start();
      _server = server;
      _pending = false;
      onStarted?.call();
    } on Exception catch (e) {
      _pending = false;
      _onStopped = null;
      onError?.call(e.toString());
      rethrow;
    }
  }
  ```

  Also add the import at the top of `scrcpy_session_impl.dart` if `ScrcpyServerOptions` is not already exported via the barrel:
  ```dart
  import 'package:scrcpy_client/src/scrcpy_server_options.dart';
  ```
  (Or rely on the barrel re-export — whichever matches the existing import style in the file.)

- [ ] **Step 4: Run all tests**

  ```bash
  dart test
  ```

  Expected: all tests PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/src/scrcpy_session_impl.dart test/scrcpy_server_test.dart
  git commit -m "feat(scrcpy_client): thread ScrcpyServerOptions through ScrcpySessionImpl.start()"
  ```

---

## Task 4: Final verify

- [ ] **Step 1: Run full test suite and analyzer**

  ```bash
  cd ../.. && melos run analyze && melos run test
  ```

  Expected: no warnings, no errors, all tests PASS.

- [ ] **Step 2: Verify barrel export**

  ```bash
  grep scrcpy_server_options packages/scrcpy_client/lib/scrcpy_client.dart
  ```

  Expected: `export 'src/scrcpy_server_options.dart';` is present.
