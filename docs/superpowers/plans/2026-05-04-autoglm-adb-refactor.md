# autoglm_adb Maintainability Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 6 maintainability issues in `packages/autoglm_adb`: split `runRaw`/`run`, extract interfaces, fix `pair()` error detection, extract `_baseArgs`, remove log-before-throw, and drop unused `path_provider`.

**Architecture:** `AdbProcessRunner` becomes an `abstract class` with two methods (`runRaw` — never throws on non-zero exit; `run` — throws on non-zero). `AdbClient` becomes an `abstract class` (all methods default to `throw UnimplementedError()`) with `AdbClientImpl` as the concrete. Existing test fakes (`FakeRunner`, `_FakeAdbClient`) require minimal updates.

**Tech Stack:** Dart, Flutter, flutter_test (no new packages needed)

---

## File Map

| Action | File |
|--------|------|
| Modify | `packages/autoglm_adb/lib/src/adb_process_runner.dart` |
| Modify | `packages/autoglm_adb/lib/src/adb_client.dart` |
| Modify | `packages/autoglm_adb/lib/autoglm_adb.dart` |
| Modify | `packages/autoglm_adb/pubspec.yaml` |
| Modify | `packages/autoglm_adb/test/adb_process_runner_test.dart` |
| Modify | `packages/autoglm_adb/test/adb_client_test.dart` |
| Modify | `scrcpy_mcp/bin/scrcpy_mcp.dart` |
| Modify | `scrcpy_app/lib/app_controller.dart` |
| Modify | `autoglm_app/lib/providers/adb_provider.dart` |
| Modify | `autoglm_app/lib/test_scrcpy.dart` |

---

## Task 1: Refactor `AdbProcessRunner` — split `run`/`runRaw`, abstract class, remove log-before-throw

**Files:**
- Modify: `packages/autoglm_adb/lib/src/adb_process_runner.dart`
- Modify: `packages/autoglm_adb/test/adb_process_runner_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `packages/autoglm_adb/test/adb_process_runner_test.dart` — inside `group('AdbProcessRunner', ...)`:

```dart
test('runRaw does not throw on non-zero exit code', () async {
  const runner = AdbProcessRunner();
  final result = await runner.runRaw('ls', ['/path-does-not-exist']);
  expect(result.exitCode, isNot(0));
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd packages/autoglm_adb && flutter test test/adb_process_runner_test.dart
```

Expected: FAIL — current `runRaw` throws `AdbException` on non-zero exit, so `runRaw` never returns.

- [ ] **Step 3: Rewrite `adb_process_runner.dart`**

Replace the entire file with:

```dart
import 'dart:async';
import 'dart:io';

import 'package:autoglm_adb/src/exceptions.dart';

/// Abstract base for running ADB processes.
///
/// Two contract levels:
/// - [runRaw] — always returns [ProcessResult]; never throws on non-zero exit.
/// - [run] — throws [AdbException] when exit code is non-zero.
abstract class AdbProcessRunner {
  const AdbProcessRunner();

  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  });

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  });
}

/// Default implementation using [Process.run].
class AdbProcessRunnerImpl extends AdbProcessRunner {
  const AdbProcessRunnerImpl();

  @override
  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await Process.run(executable, arguments).timeout(timeout);
    } on TimeoutException {
      throw AdbException(
        'Command timeout after ${timeout.inSeconds}s '
        '($executable ${arguments.join(' ')})',
      );
    } on ProcessException catch (e) {
      throw AdbException('Failed to start process: ${e.message}');
    }
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await runRaw(executable, arguments, timeout: timeout);
    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      final out = result.stdout.toString().trim();
      throw AdbException(
        'Command failed ($executable ${arguments.join(' ')}):\n$err\n$out',
      );
    }
    return result;
  }
}
```

- [ ] **Step 4: Update `adb_process_runner_test.dart`**

Replace the entire file with:

```dart
import 'package:autoglm_adb/src/adb_process_runner.dart';
import 'package:autoglm_adb/src/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdbProcessRunnerImpl', () {
    test('runRaw returns result on success', () async {
      const runner = AdbProcessRunnerImpl();
      final result = await runner.runRaw('echo', ['hello']);
      expect(result.exitCode, 0);
      expect(result.stdout.toString().trim(), 'hello');
    });

    test('runRaw does not throw on non-zero exit code', () async {
      const runner = AdbProcessRunnerImpl();
      final result = await runner.runRaw('ls', ['/path-does-not-exist']);
      expect(result.exitCode, isNot(0));
    });

    test('run throws AdbException on non-zero exit code', () async {
      const runner = AdbProcessRunnerImpl();
      expect(
        () => runner.run('ls', ['/path-does-not-exist']),
        throwsA(isA<AdbException>()),
      );
    });

    test('runRaw throws AdbException on timeout', () async {
      const runner = AdbProcessRunnerImpl();
      expect(
        () => runner.runRaw(
          'sleep',
          ['2'],
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<AdbException>().having((e) => e.message, 'message', contains('timeout')),
        ),
      );
    });

    test('run throws AdbException on timeout', () async {
      const runner = AdbProcessRunnerImpl();
      expect(
        () => runner.run(
          'sleep',
          ['2'],
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<AdbException>().having((e) => e.message, 'message', contains('timeout')),
        ),
      );
    });
  });
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd packages/autoglm_adb && flutter test test/adb_process_runner_test.dart
```

Expected: All 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/autoglm_adb/lib/src/adb_process_runner.dart \
        packages/autoglm_adb/test/adb_process_runner_test.dart
git commit -m "$(cat <<'EOF'
refactor(autoglm_adb): split AdbProcessRunner into runRaw/run, extract abstract class

runRaw never throws on non-zero exit — callers inspect the result themselves.
run throws AdbException on non-zero exit — used for commands where failure is always unexpected.
Removes log-before-throw so callers control observability.
AdbProcessRunnerImpl is the concrete default; abstract AdbProcessRunner is the testable seam.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Refactor `AdbClient` — abstract class, `_baseArgs`, fix `pair()`, correct `run`/`runRaw` routing

**Files:**
- Modify: `packages/autoglm_adb/lib/src/adb_client.dart`
- Modify: `packages/autoglm_adb/test/adb_client_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `packages/autoglm_adb/test/adb_client_test.dart` — inside `group('AdbClient', ...)`:

```dart
test('shell returns result even on non-zero exit code', () async {
  final client = AdbClientImpl(runner: FakeRunner('error output', 1));
  final result = await client.shell(['ls', '/nonexistent']);
  expect(result.exitCode, 1);
  expect(result.stdout.toString(), 'error output');
});
```

This test references `AdbClientImpl` and `FakeRunner` with exitCode=1. It will fail because:
- `AdbClientImpl` doesn't exist yet
- `FakeRunner.runRaw` currently throws on non-zero exit

- [ ] **Step 2: Run test to verify it fails**

```bash
cd packages/autoglm_adb && flutter test test/adb_client_test.dart
```

Expected: FAIL — compile error (`AdbClientImpl` not defined) or `AdbException` thrown instead of returning.

- [ ] **Step 3: Rewrite `adb_client.dart`**

Replace the entire file with:

```dart
import 'dart:io';

import 'package:autoglm_adb/src/adb_process_runner.dart';
import 'package:autoglm_adb/src/exceptions.dart';
import 'package:autoglm_adb/src/device_info.dart';

/// Abstract ADB client interface.
///
/// All methods default to [UnimplementedError] so partial fakes can extend
/// this class and only override the methods they exercise.
abstract class AdbClient {
  const AdbClient();

  Future<String> getVersion() => throw UnimplementedError();

  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      throw UnimplementedError();

  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) =>
      throw UnimplementedError();

  Future<void> forwardRemove(String local, {String? deviceId}) =>
      throw UnimplementedError();

  Future<void> reverse(
    String remote,
    String local, {
    String? deviceId,
    bool noRebind = false,
  }) =>
      throw UnimplementedError();

  Future<void> reverseRemove(String remote, {String? deviceId}) =>
      throw UnimplementedError();

  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) =>
      throw UnimplementedError();

  Future<String> pair(String ip, int port, String code) =>
      throw UnimplementedError();

  Future<String> connect(String ip, int port) => throw UnimplementedError();

  Future<List<String>> getDevices() => throw UnimplementedError();

  Future<List<DeviceInfo>> getDevicesWithInfo() => throw UnimplementedError();
}

/// Concrete ADB client implementation.
class AdbClientImpl extends AdbClient {
  const AdbClientImpl({
    this.adbPath = 'adb',
    this.runner = const AdbProcessRunnerImpl(),
  });

  final String adbPath;
  final AdbProcessRunner runner;

  List<String> _baseArgs(String? deviceId) =>
      deviceId != null ? ['-s', deviceId] : const [];

  @override
  Future<String> getVersion() async {
    final result = await runner.run(adbPath, ['version']);
    return result.stdout.toString().trim();
  }

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return runner.runRaw(
      adbPath,
      [..._baseArgs(deviceId), 'shell', ...arguments],
      timeout: timeout,
    );
  }

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'forward',
      if (noRebind) '--no-rebind',
      local,
      remote,
    ]);
  }

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'forward',
      '--remove',
      local,
    ]);
  }

  @override
  Future<void> reverse(
    String remote,
    String local, {
    String? deviceId,
    bool noRebind = false,
  }) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'reverse',
      if (noRebind) '--no-rebind',
      remote,
      local,
    ]);
  }

  @override
  Future<void> reverseRemove(String remote, {String? deviceId}) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'reverse',
      '--remove',
      remote,
    ]);
  }

  @override
  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'push',
      localPath,
      remotePath,
    ]);
  }

  @override
  Future<String> pair(String ip, int port, String code) async {
    if (code.length != 6 || int.tryParse(code) == null) {
      throw const AdbException('Pairing code must be 6 digits.');
    }
    final address = '$ip:$port';
    final result = await runner.runRaw(adbPath, ['pair', address, code]);
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();
    if (stdout.toLowerCase().contains('successfully paired') ||
        stdout.toLowerCase().contains('success')) {
      return 'Successfully paired to $address';
    }
    final combined = '$stdout $stderr'.toLowerCase();
    if (combined.contains('refused')) {
      throw const AdbException(
        'Connection refused - check if wireless debugging is enabled',
      );
    }
    throw AdbException(
      'Pairing failed: ${stdout.isNotEmpty ? stdout : stderr}',
    );
  }

  @override
  Future<String> connect(String ip, int port) async {
    final address = '$ip:$port';
    final result = await runner.runRaw(adbPath, ['connect', address]);
    final output = result.stdout.toString().trim();
    if (output.contains('connected to $address') ||
        output.contains('already connected')) {
      return output;
    }
    throw AdbException('Connect failed: $output');
  }

  @override
  Future<List<String>> getDevices() async {
    final result = await runner.run(adbPath, ['devices']);
    final lines = result.stdout.toString().split('\n');
    return [
      for (var i = 1; i < lines.length; i++)
        if (lines[i].trim().isNotEmpty && lines[i].contains('\t'))
          lines[i].trim().split('\t').first,
    ];
  }

  @override
  Future<List<DeviceInfo>> getDevicesWithInfo() async {
    final result = await runner.run(adbPath, ['devices']);
    final lines = result.stdout.toString().split('\n');

    final entries = <({String serial, DeviceStatus status})>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || !line.contains('\t')) continue;
      final parts = line.split('\t');
      final serial = parts[0].trim();
      final rawStatus = parts[1].trim();
      final status = switch (rawStatus) {
        'device' => DeviceStatus.online,
        'offline' => DeviceStatus.offline,
        _ => DeviceStatus.unauthorized,
      };
      entries.add((serial: serial, status: status));
    }

    return Future.wait(
      entries.map((e) async {
        if (e.status != DeviceStatus.online) {
          return DeviceInfo(serial: e.serial, status: e.status);
        }
        try {
          final propResult = await runner.run(
            adbPath,
            ['-s', e.serial, 'shell', 'getprop'],
          );
          final props = _parseGetprop(propResult.stdout.toString());
          return DeviceInfo(
            serial: e.serial,
            status: e.status,
            model: props['ro.product.model'],
            manufacturer: props['ro.product.manufacturer'],
            androidVersion: props['ro.build.version.release'],
            sdkVersion: int.tryParse(props['ro.build.version.sdk'] ?? ''),
          );
        } catch (_) {
          return DeviceInfo(serial: e.serial, status: e.status);
        }
      }),
    );
  }

  static Map<String, String> _parseGetprop(String output) {
    final regex = RegExp(r'\[([^\]]+)\]:\s*\[([^\]]*)\]');
    final result = <String, String>{};
    for (final match in regex.allMatches(output)) {
      result[match.group(1)!] = match.group(2)!;
    }
    return result;
  }
}
```

- [ ] **Step 4: Update `adb_client_test.dart`**

Replace the entire file with:

```dart
import 'dart:io';

import 'package:autoglm_adb/src/adb_client.dart';
import 'package:autoglm_adb/src/adb_process_runner.dart';
import 'package:autoglm_adb/src/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRunner extends AdbProcessRunner {
  const FakeRunner(
    this.stdoutResponse, [
    this.exitCode = 0,
    this.stderrResponse = '',
  ]);

  final String stdoutResponse;
  final String stderrResponse;
  final int exitCode;

  @override
  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return ProcessResult(0, exitCode, stdoutResponse, stderrResponse);
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (exitCode != 0) throw const AdbException('Command failed');
    return ProcessResult(0, exitCode, stdoutResponse, stderrResponse);
  }
}

void main() {
  group('AdbClientImpl', () {
    test('pair validates 6 digit code', () async {
      final client = AdbClientImpl(runner: const FakeRunner(''));
      expect(
        () => client.pair('192.168.1.1', 5555, '123'),
        throwsA(isA<AdbException>()),
      );
    });

    test('pair success parses output', () async {
      final client = AdbClientImpl(
        runner: const FakeRunner('Successfully paired to 192.168.1.1:5555 [guid]'),
      );
      final res = await client.pair('192.168.1.1', 5555, '123456');
      expect(res, contains('Successfully paired'));
    });

    test('pair throws on connection refused', () async {
      final client = AdbClientImpl(
        runner: const FakeRunner('', 1, 'error: Connection refused'),
      );
      expect(
        () => client.pair('192.168.1.1', 5555, '123456'),
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            contains('Connection refused'),
          ),
        ),
      );
    });

    test('devices parses output correctly', () async {
      const stdout = '''
List of devices attached
192.168.1.1:5555\tdevice
emulator-5554\toffline
''';
      final client = AdbClientImpl(runner: const FakeRunner(stdout));
      final devices = await client.getDevices();
      expect(devices, ['192.168.1.1:5555', 'emulator-5554']);
    });

    test('shell returns result even on non-zero exit code', () async {
      final client = AdbClientImpl(runner: const FakeRunner('error output', 1));
      final result = await client.shell(['ls', '/nonexistent']);
      expect(result.exitCode, 1);
      expect(result.stdout.toString(), 'error output');
    });
  });
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd packages/autoglm_adb && flutter test test/adb_client_test.dart
```

Expected: All 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/autoglm_adb/lib/src/adb_client.dart \
        packages/autoglm_adb/test/adb_client_test.dart
git commit -m "$(cat <<'EOF'
refactor(autoglm_adb): extract AdbClient abstract class, AdbClientImpl concrete

- AdbClient is now an abstract base with UnimplementedError defaults so partial
  test fakes can extend it without implementing all 11 methods
- AdbClientImpl is the concrete implementation (rename from AdbClient)
- _baseArgs() helper eliminates 8 copies of deviceId arg-building
- shell() routes through runRaw (exit code belongs to the shell command)
- pair()/connect() inspect stdout/stderr directly instead of parsing
  a wrapped AdbException message — avoids silent failure on ADB output changes
- forward/reverse/push/getDevices route through run (non-zero always means error)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Update `autoglm_adb.dart` exports

**Files:**
- Modify: `packages/autoglm_adb/lib/autoglm_adb.dart`

- [ ] **Step 1: Update barrel exports to expose new names**

Replace the entire file with:

```dart
/// ADB client and binary management for AutoGLM.
library;

export 'src/adb_binary_manager.dart';
export 'src/adb_client.dart'; // exports both AdbClient and AdbClientImpl
export 'src/adb_process_runner.dart'; // exports both AdbProcessRunner and AdbProcessRunnerImpl
export 'src/device_info.dart';
export 'src/exceptions.dart';
```

- [ ] **Step 2: Run analyze to confirm no issues in the package**

```bash
cd packages/autoglm_adb && flutter analyze
```

Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add packages/autoglm_adb/lib/autoglm_adb.dart
git commit -m "$(cat <<'EOF'
chore(autoglm_adb): update barrel exports for renamed classes

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Update downstream instantiation sites

**Files:**
- Modify: `scrcpy_mcp/bin/scrcpy_mcp.dart` (line 10)
- Modify: `scrcpy_app/lib/app_controller.dart` (lines 13, 18)
- Modify: `autoglm_app/lib/providers/adb_provider.dart` (line 19)
- Modify: `autoglm_app/lib/test_scrcpy.dart` (line 106)

These files all instantiate `AdbClient(...)` which no longer has a constructor (it is now abstract). Update each to `AdbClientImpl(...)`.

- [ ] **Step 1: Update `scrcpy_mcp/bin/scrcpy_mcp.dart`**

Find:
```dart
final adb = AdbClient(adbPath: adbPath);
```
Replace with:
```dart
final adb = AdbClientImpl(adbPath: adbPath);
```

- [ ] **Step 2: Update `scrcpy_app/lib/app_controller.dart`**

Find both occurrences of:
```dart
adb: const ScrcpyAppAdb(AdbClient()),
```
Replace each with:
```dart
adb: const ScrcpyAppAdb(AdbClientImpl()),
```

- [ ] **Step 3: Update `autoglm_app/lib/providers/adb_provider.dart`**

Find:
```dart
return AdbClient(adbPath: adbPath);
```
Replace with:
```dart
return AdbClientImpl(adbPath: adbPath);
```

- [ ] **Step 4: Update `autoglm_app/lib/test_scrcpy.dart`**

Find:
```dart
const adbClient = AdbClient();
```
Replace with:
```dart
const adbClient = AdbClientImpl();
```

- [ ] **Step 5: Run analyze across all affected packages**

```bash
flutter analyze scrcpy_mcp scrcpy_app autoglm_app
```

Expected: No issues related to `AdbClient` constructor.

- [ ] **Step 6: Run all package tests**

```bash
melos run test
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add scrcpy_mcp/bin/scrcpy_mcp.dart \
        scrcpy_app/lib/app_controller.dart \
        autoglm_app/lib/providers/adb_provider.dart \
        autoglm_app/lib/test_scrcpy.dart
git commit -m "$(cat <<'EOF'
fix: update AdbClient instantiation sites to AdbClientImpl

AdbClient is now abstract; AdbClientImpl is the concrete default.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Remove unused `path_provider` dependency

**Files:**
- Modify: `packages/autoglm_adb/pubspec.yaml`

- [ ] **Step 1: Remove `path_provider` from `pubspec.yaml`**

In `packages/autoglm_adb/pubspec.yaml`, remove this line from `dependencies`:

```yaml
  path_provider: ^2.1.4
```

- [ ] **Step 2: Re-bootstrap the workspace**

```bash
melos bootstrap
```

Expected: completes without errors.

- [ ] **Step 3: Verify no source file imports `path_provider`**

```bash
grep -r "path_provider" packages/autoglm_adb/lib
```

Expected: no output.

- [ ] **Step 4: Run all tests**

```bash
melos run test
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/autoglm_adb/pubspec.yaml
git commit -m "$(cat <<'EOF'
chore(autoglm_adb): remove unused path_provider dependency

No source file in the package imports path_provider; binDir is caller-supplied.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage check:**

| Issue | Covered by |
|-------|-----------|
| P0: `runRaw` throws on non-zero exit | Task 1 — split into `runRaw`/`run` |
| P1: `AdbProcessRunner` no interface | Task 1 — `abstract class AdbProcessRunner` |
| P1: `AdbClient` no interface | Task 2 — `abstract class AdbClient` |
| P1: `pair()` fragile error parsing | Task 2 — checks `stdout`/`stderr` directly |
| P2: `_baseArgs` repeated 8× | Task 2 — `_baseArgs()` helper |
| P2: log-before-throw | Task 1 — `AppLogger.maybeLog` removed from runner |
| P2: unused `path_provider` | Task 5 |
| Downstream call sites | Task 4 |
| Barrel exports | Task 3 |

**Placeholder scan:** No TBDs or "similar to Task N" patterns found.

**Type consistency:**
- `AdbProcessRunnerImpl` introduced in Task 1, referenced as default in `AdbClientImpl` constructor in Task 2 — consistent.
- `AdbClientImpl` introduced in Task 2, updated in downstream files in Task 4 — consistent.
- `FakeRunner` in test updated in Task 2 to match new `AdbProcessRunner` interface — consistent.
