# scrcpy_plus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu-bar app for managing Android device pairing, connection, and launching scrcpy.

**Architecture:** Pure status-bar Flutter Desktop app with no main window. Uses `tray_manager` for system tray, `adb_tools` for device management, and `Process.start` to invoke the system `scrcpy` CLI.

**Tech Stack:** Flutter Desktop (macOS), tray_manager, adb_tools, logger_utils, shared_preferences

**Design Spec:** `docs/superpowers/specs/2026-05-19-scrcpy-plus-design.md`

---

## File Structure

```
scrcpy_plus/
├── lib/
│   ├── main.dart                          # Entry point, no window, init tray
│   ├── app/
│   │   ├── tray_manager.dart              # System tray icon and menu lifecycle
│   │   ├── menu_builder.dart              # Builds Menu from current state
│   │   └── app_controller.dart            # Orchestrates all managers
│   ├── device/
│   │   ├── device_manager.dart            # Device discovery and connection
│   │   ├── device_entry.dart              # Extended device model with battery
│   │   └── pairing_service.dart           # IP/ADB connect pairing logic
│   ├── scrcpy/
│   │   ├── scrcpy_launcher.dart           # Launch scrcpy as subprocess
│   │   └── scrcpy_config.dart             # Scrcpy parameters model
│   ├── settings/
│   │   ├── settings_manager.dart          # Read/write JSON config
│   │   └── settings_dialog.dart           # macOS dialog for settings
│   └── utils/
│       └── process_runner.dart            # Process.start wrapper
├── assets/
│   ├── tray_icon.png                      # Gray icon (disconnected)
│   └── tray_icon_connected.png            # Color icon (connected)
├── test/
│   ├── device/
│   │   ├── device_manager_test.dart
│   │   ├── device_entry_test.dart
│   │   └── pairing_service_test.dart
│   ├── scrcpy/
│   │   ├── scrcpy_launcher_test.dart
│   │   └── scrcpy_config_test.dart
│   ├── settings/
│   │   └── settings_manager_test.dart
│   └── app/
│       ├── menu_builder_test.dart
│       └── app_controller_test.dart
└── pubspec.yaml
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `scrcpy_plus/pubspec.yaml`
- Create: `scrcpy_plus/lib/main.dart`
- Create: `scrcpy_plus/assets/tray_icon.png` (placeholder)
- Create: `scrcpy_plus/assets/tray_icon_connected.png` (placeholder)
- Create: `scrcpy_plus/macos/` (via flutter create)
- Modify: `pubspec.yaml` (workspace root)

- [ ] **Step 1: Create Flutter project skeleton**

```bash
cd /Users/hao/ai/mobile/asf_dev
flutter create --platforms=macos --org com.example scrcpy_plus_temp
mv scrcpy_plus_temp/macos scrcpy_plus/macos
mv scrcpy_plus_temp/.gitignore scrcpy_plus/.gitignore 2>/dev/null || true
mv scrcpy_plus_temp/.metadata scrcpy_plus/.metadata 2>/dev/null || true
rm -rf scrcpy_plus_temp
```

- [ ] **Step 2: Write pubspec.yaml**

```yaml
# scrcpy_plus/pubspec.yaml
name: scrcpy_plus
description: macOS menu-bar app for Android device management and scrcpy launcher.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.5.0
  flutter: ">=3.24.0"

resolution: workspace

dependencies:
  adb_tools:
    path: ../packages/adb_tools
  logger_utils:
    path: ../packages/logger_utils
  flutter:
    sdk: flutter
  tray_manager: ^0.4.0
  path: ^1.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  test: any

flutter:
  assets:
    - assets/
  uses-material-design: true
```

- [ ] **Step 3: Create placeholder tray icons**

Create two 22x22 PNG icons in `scrcpy_plus/assets/`:
- `tray_icon.png` — gray version
- `tray_icon_connected.png` — color version

Use any placeholder for now (copy from scrcpy_app/assets/tray_icon.png).

```bash
cp scrcpy_app/assets/tray_icon.png scrcpy_plus/assets/tray_icon.png
cp scrcpy_app/assets/tray_icon.png scrcpy_plus/assets/tray_icon_connected.png
```

- [ ] **Step 4: Write minimal main.dart**

```dart
// scrcpy_plus/lib/main.dart
import 'package:flutter/widgets.dart';

void main() {
  // No window — pure menu-bar app
  runApp(const _Placeholder());
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
```

- [ ] **Step 5: Add to workspace root pubspec.yaml**

Add `scrcpy_plus` to the workspace list in the root `pubspec.yaml`:

```yaml
workspace:
  - packages/adb_tools
  - packages/logger_utils
  - packages/scrcpy_client
  - scrcpy_app
  - scrcpy_flutter
  - scrcpy_mcp
  - scrcpy_plus
  - scrcpy_view
```

- [ ] **Step 6: Bootstrap and verify**

```bash
cd /Users/hao/ai/mobile/asf_dev
melos bootstrap
cd scrcpy_plus
flutter pub get
```

- [ ] **Step 7: Commit**

```bash
git add scrcpy_plus/ pubspec.yaml
git commit -m "feat(scrcpy_plus): scaffold project with Flutter Desktop skeleton"
```

---

### Task 2: Process Runner Utility

**Files:**
- Create: `scrcpy_plus/lib/utils/process_runner.dart`
- Create: `scrcpy_plus/test/utils/process_runner_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/utils/process_runner_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/utils/process_runner.dart';

void main() {
  group('ProcessRunner', () {
    test('run returns stdout on success', () async {
      final runner = ProcessRunner();
      final result = await runner.run('echo', ['hello']);
      expect(result.exitCode, 0);
      expect(result.stdout.toString().trim(), 'hello');
    });

    test('run returns non-zero exit on failure', () async {
      final runner = ProcessRunner();
      final result = await runner.run('false', []);
      expect(result.exitCode, isNot(0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/utils/process_runner_test.dart
```

Expected: FAIL — `ProcessRunner` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/utils/process_runner.dart
import 'dart:io';

/// Wrapper around [Process.run] for testability.
class ProcessRunner {
  const ProcessRunner();

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return Process.run(
      executable,
      arguments,
      timeout: timeout,
    );
  }

  Future<Process> start(
    String executable,
    List<String> arguments,
  ) {
    return Process.start(executable, arguments);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/utils/process_runner_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/utils/process_runner.dart scrcpy_plus/test/utils/process_runner_test.dart
git commit -m "feat(scrcpy_plus): add ProcessRunner utility"
```

---

### Task 3: Device Entry Model

**Files:**
- Create: `scrcpy_plus/lib/device/device_entry.dart`
- Create: `scrcpy_plus/test/device/device_entry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/device/device_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

void main() {
  group('DeviceEntry', () {
    test('isWifi detects IP:port serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: '192.168.1.100:5555',
          status: DeviceStatus.online,
        ),
      );
      expect(entry.isWifi, true);
    });

    test('isWifi returns false for USB serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: 'ABCD1234',
          status: DeviceStatus.online,
        ),
      );
      expect(entry.isWifi, false);
    });

    test('displayName uses model when available', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: 'ABCD1234',
          status: DeviceStatus.online,
          model: 'Pixel 7',
        ),
      );
      expect(entry.displayName, 'Pixel 7');
    });

    test('displayName falls back to serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: 'ABCD1234',
          status: DeviceStatus.online,
        ),
      );
      expect(entry.displayName, 'ABCD1234');
    });

    test('connectionLabel shows WiFi for IP serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: '192.168.1.100:5555',
          status: DeviceStatus.online,
        ),
      );
      expect(entry.connectionLabel, 'WiFi');
    });

    test('connectionLabel shows USB for non-IP serial', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: 'ABCD1234',
          status: DeviceStatus.online,
        ),
      );
      expect(entry.connectionLabel, 'USB');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/device/device_entry_test.dart
```

Expected: FAIL — `DeviceEntry` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/device/device_entry.dart
import 'package:adb_tools/adb_tools.dart';

/// Extended device model with battery and display info for menu display.
class DeviceEntry {
  DeviceEntry({
    required this.info,
    this.battery,
  });

  final DeviceInfo info;
  final int? battery; // percentage, null if unknown

  bool get isWifi => info.isWifi;
  String get displayName => info.displayName;
  String get serial => info.serial;

  String get connectionLabel => isWifi ? 'WiFi' : 'USB';

  /// Menu label: "Pixel 7 (WiFi)" or "ABCD1234 (USB)"
  String get menuLabel {
    final conn = connectionLabel;
    return '$displayName ($conn)';
  }

  /// Detail line: "Battery: 85% | Android 14 | 1080x2400"
  String? get detailLine {
    final parts = <String>[];
    if (battery != null) parts.add('Battery: $battery%');
    if (info.androidVersion != null) parts.add('Android ${info.androidVersion}');
    if (info.screenWidth > 0) {
      parts.add('${info.screenWidth.toInt()}x${info.screenHeight.toInt()}');
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/device/device_entry_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/device/device_entry.dart scrcpy_plus/test/device/device_entry_test.dart
git commit -m "feat(scrcpy_plus): add DeviceEntry model"
```

---

### Task 4: Scrcpy Config Model

**Files:**
- Create: `scrcpy_plus/lib/scrcpy/scrcpy_config.dart`
- Create: `scrcpy_plus/test/scrcpy/scrcpy_config_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/scrcpy/scrcpy_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';

void main() {
  group('ScrcpyConfig', () {
    test('default values', () {
      const config = ScrcpyConfig();
      expect(config.scrcpyPath, 'scrcpy');
      expect(config.maxSize, 1024);
      expect(config.videoBitRate, '8M');
      expect(config.videoCodec, 'h264');
    });

    test('toArgs produces correct CLI arguments', () {
      const config = ScrcpyConfig(
        maxSize: 1280,
        videoBitRate: '4M',
        videoCodec: 'h265',
      );
      final args = config.toArgs('ABCD1234');
      expect(args, [
        '--serial', 'ABCD1234',
        '--max-size', '1280',
        '--video-bit-rate', '4M',
        '--video-codec', 'h265',
      ]);
    });

    test('toJson and fromJson round-trip', () {
      const config = ScrcpyConfig(
        scrcpyPath: '/usr/local/bin/scrcpy',
        maxSize: 1280,
        videoBitRate: '4M',
        videoCodec: 'h265',
      );
      final json = config.toJson();
      final restored = ScrcpyConfig.fromJson(json);
      expect(restored.scrcpyPath, config.scrcpyPath);
      expect(restored.maxSize, config.maxSize);
      expect(restored.videoBitRate, config.videoBitRate);
      expect(restored.videoCodec, config.videoCodec);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/scrcpy/scrcpy_config_test.dart
```

Expected: FAIL — `ScrcpyConfig` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/scrcpy/scrcpy_config.dart

/// Configuration for scrcpy CLI parameters.
class ScrcpyConfig {
  const ScrcpyConfig({
    this.scrcpyPath = 'scrcpy',
    this.maxSize = 1024,
    this.videoBitRate = '8M',
    this.videoCodec = 'h264',
  });

  final String scrcpyPath;
  final int maxSize;
  final String videoBitRate;
  final String videoCodec;

  /// Build CLI argument list for a given device serial.
  List<String> toArgs(String serial) {
    return [
      '--serial', serial,
      '--max-size', '$maxSize',
      '--video-bit-rate', videoBitRate,
      '--video-codec', videoCodec,
    ];
  }

  Map<String, dynamic> toJson() => {
        'scrcpyPath': scrcpyPath,
        'maxSize': maxSize,
        'videoBitRate': videoBitRate,
        'videoCodec': videoCodec,
      };

  factory ScrcpyConfig.fromJson(Map<String, dynamic> json) {
    return ScrcpyConfig(
      scrcpyPath: json['scrcpyPath'] as String? ?? 'scrcpy',
      maxSize: json['maxSize'] as int? ?? 1024,
      videoBitRate: json['videoBitRate'] as String? ?? '8M',
      videoCodec: json['videoCodec'] as String? ?? 'h264',
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/scrcpy/scrcpy_config_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/scrcpy/scrcpy_config.dart scrcpy_plus/test/scrcpy/scrcpy_config_test.dart
git commit -m "feat(scrcpy_plus): add ScrcpyConfig model"
```

---

### Task 5: Settings Manager

**Files:**
- Create: `scrcpy_plus/lib/settings/settings_manager.dart`
- Create: `scrcpy_plus/test/settings/settings_manager_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/settings/settings_manager_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';

void main() {
  late Directory tempDir;
  late SettingsManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('scrcpy_plus_test_');
    manager = SettingsManager(configDir: tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SettingsManager', () {
    test('loadConfig returns defaults when no file exists', () async {
      final config = await manager.loadConfig();
      expect(config.scrcpyPath, 'scrcpy');
      expect(config.maxSize, 1024);
    });

    test('saveConfig then loadConfig round-trips', () async {
      const config = ScrcpyConfig(
        scrcpyPath: '/usr/local/bin/scrcpy',
        maxSize: 1280,
        videoBitRate: '4M',
        videoCodec: 'h265',
      );
      await manager.saveConfig(config);
      final loaded = await manager.loadConfig();
      expect(loaded.scrcpyPath, '/usr/local/bin/scrcpy');
      expect(loaded.maxSize, 1280);
      expect(loaded.videoBitRate, '4M');
      expect(loaded.videoCodec, 'h265');
    });

    test('loadKnownSerials returns empty list when no file', () async {
      final serials = await manager.loadKnownSerials();
      expect(serials, isEmpty);
    });

    test('saveKnownSerials then loadKnownSerials round-trips', () async {
      await manager.saveKnownSerials(['dev1', 'dev2']);
      final loaded = await manager.loadKnownSerials();
      expect(loaded, ['dev1', 'dev2']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/settings/settings_manager_test.dart
```

Expected: FAIL — `SettingsManager` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/settings/settings_manager.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';

/// Persists app settings and known device serials to JSON files.
class SettingsManager {
  SettingsManager({required this.configDir});

  final String configDir;

  String get _configPath => p.join(configDir, 'settings.json');
  String get _knownSerialsPath => p.join(configDir, 'known_devices.json');

  Future<ScrcpyConfig> loadConfig() async {
    final file = File(_configPath);
    if (!await file.exists()) return const ScrcpyConfig();
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return ScrcpyConfig.fromJson(json);
  }

  Future<void> saveConfig(ScrcpyConfig config) async {
    final file = File(_configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(config.toJson()));
  }

  Future<List<String>> loadKnownSerials() async {
    final file = File(_knownSerialsPath);
    if (!await file.exists()) return [];
    final json = jsonDecode(await file.readAsString()) as List;
    return json.cast<String>();
  }

  Future<void> saveKnownSerials(List<String> serials) async {
    final file = File(_knownSerialsPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(serials));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/settings/settings_manager_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/settings/settings_manager.dart scrcpy_plus/test/settings/settings_manager_test.dart
git commit -m "feat(scrcpy_plus): add SettingsManager for config and known devices"
```

---

### Task 6: Pairing Service

**Files:**
- Create: `scrcpy_plus/lib/device/pairing_service.dart`
- Create: `scrcpy_plus/test/device/pairing_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/device/pairing_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_plus/device/pairing_service.dart';

void main() {
  group('PairingService', () {
    test('validateAddress accepts valid IP:port', () {
      expect(PairingService.validateAddress('192.168.1.100:5555'), isNull);
    });

    test('validateAddress rejects missing port', () {
      expect(PairingService.validateAddress('192.168.1.100'), isNotNull);
    });

    test('validateAddress rejects empty string', () {
      expect(PairingService.validateAddress(''), isNotNull);
    });

    test('validatePairingCode accepts 6-digit code', () {
      expect(PairingService.validatePairingCode('123456'), isNull);
    });

    test('validatePairingCode rejects short code', () {
      expect(PairingService.validatePairingCode('12345'), isNotNull);
    });

    test('validatePairingCode rejects non-numeric', () {
      expect(PairingService.validatePairingCode('abcdef'), isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/device/pairing_service_test.dart
```

Expected: FAIL — `PairingService` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/device/pairing_service.dart
import 'package:adb_tools/adb_tools.dart';

/// Handles device pairing via IP+code and direct ADB connect.
class PairingService {
  PairingService({required this.adb});

  final AdbClient adb;

  /// Validate an IP:port address string. Returns null if valid, error message otherwise.
  static String? validateAddress(String address) {
    if (address.isEmpty) return 'Address cannot be empty';
    final parts = address.split(':');
    if (parts.length != 2) return 'Format must be IP:port';
    final port = int.tryParse(parts[1]);
    if (port == null || port <= 0 || port > 65535) return 'Invalid port number';
    return null;
  }

  /// Validate a 6-digit pairing code. Returns null if valid, error message otherwise.
  static String? validatePairingCode(String code) {
    if (code.length != 6) return 'Code must be 6 digits';
    if (int.tryParse(code) == null) return 'Code must be numeric';
    return null;
  }

  /// Pair with a device using IP, port, and pairing code.
  Future<String> pair(String ip, int port, String code) async {
    return adb.pair(ip, port, code);
  }

  /// Connect to a previously paired device.
  Future<String> connect(String ip, int port) async {
    return adb.connect(ip, port);
  }

  /// Disconnect a device.
  Future<void> disconnect(String serial) async {
    await adb.runner.run(adb.adbPath, ['disconnect', serial]);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/device/pairing_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/device/pairing_service.dart scrcpy_plus/test/device/pairing_service_test.dart
git commit -m "feat(scrcpy_plus): add PairingService with validation"
```

---

### Task 7: Device Manager

**Files:**
- Create: `scrcpy_plus/lib/device/device_manager.dart`
- Create: `scrcpy_plus/test/device/device_manager_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/device/device_manager_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/device/device_manager.dart';

void main() {
  group('DeviceManager', () {
    test('devices list is initially empty', () {
      final manager = DeviceManager();
      expect(manager.devices, isEmpty);
    });

    test('notifyListeners fires on change', () {
      final manager = DeviceManager();
      var notified = false;
      manager.addListener(() => notified = true);
      manager.setDevices([]);
      expect(notified, true);
    });

    test('hasConnected reflects device list state', () {
      final manager = DeviceManager();
      expect(manager.hasConnected, false);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/device/device_manager_test.dart
```

Expected: FAIL — `DeviceManager` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/device/device_manager.dart
import 'dart:async';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

/// Manages device discovery, polling, and state.
class DeviceManager {
  DeviceManager({required this.adb});

  final AdbClient adb;
  final List<DeviceEntry> _devices = [];
  Timer? _pollTimer;
  final List<VoidCallback> _listeners = [];

  List<DeviceEntry> get devices => List.unmodifiable(_devices);
  bool get hasConnected => _devices.isNotEmpty;

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Set devices and notify listeners.
  void setDevices(List<DeviceEntry> devices) {
    _devices
      ..clear()
      ..addAll(devices);
    _notify();
  }

  /// Start periodic polling every [interval] seconds.
  void startPolling({Duration interval = const Duration(seconds: 30)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => refresh());
  }

  /// Stop polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Refresh device list from ADB.
  Future<void> refresh() async {
    try {
      final serials = await adb.getDevices();
      final entries = <DeviceEntry>[];
      for (final serial in serials) {
        try {
          final info = await adb.getDeviceInfo(serial);
          entries.add(DeviceEntry(info: info));
        } catch (e) {
          appLogger.warning('Failed to get info for $serial: $e');
          entries.add(
            DeviceEntry(
              info: DeviceInfo(
                serial: serial,
                status: DeviceStatus.online,
              ),
            ),
          );
        }
      }
      setDevices(entries);
    } catch (e) {
      appLogger.severe('Device refresh failed: $e');
    }
  }

  void dispose() {
    stopPolling();
    _listeners.clear();
  }
}

typedef VoidCallback = void Function();
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/device/device_manager_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/device/device_manager.dart scrcpy_plus/test/device/device_manager_test.dart
git commit -m "feat(scrcpy_plus): add DeviceManager with polling"
```

---

### Task 8: Scrcpy Launcher

**Files:**
- Create: `scrcpy_plus/lib/scrcpy/scrcpy_launcher.dart`
- Create: `scrcpy_plus/test/scrcpy/scrcpy_launcher_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/scrcpy/scrcpy_launcher_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_launcher.dart';

void main() {
  group('ScrcpyLauncher', () {
    test('isRunning tracks process state', () {
      final launcher = ScrcpyLauncher();
      expect(launcher.isRunning, false);
    });

    test('config getter returns current config', () {
      const config = ScrcpyConfig(maxSize: 1280);
      final launcher = ScrcpyLauncher(config: config);
      expect(launcher.config.maxSize, 1280);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/scrcpy/scrcpy_launcher_test.dart
```

Expected: FAIL — `ScrcpyLauncher` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/scrcpy/scrcpy_launcher.dart
import 'dart:io';

import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';

/// Launches and manages scrcpy as a subprocess.
class ScrcpyLauncher {
  ScrcpyLauncher({this.config = const ScrcpyConfig()});

  ScrcpyConfig config;
  Process? _process;

  bool get isRunning => _process != null;

  /// Launch scrcpy for the given device serial.
  Future<void> launch(String serial) async {
    if (_process != null) {
      appLogger.warning('scrcpy already running, killing previous instance');
      await kill();
    }

    final args = config.toArgs(serial);
    appLogger.info('Launching: ${config.scrcpyPath} ${args.join(' ')}');

    try {
      _process = await Process.start(config.scrcpyPath, args);
      _process!.exitCode.then((code) {
        appLogger.info('scrcpy exited with code $code');
        _process = null;
      });
    } catch (e) {
      _process = null;
      appLogger.severe('Failed to launch scrcpy: $e');
      rethrow;
    }
  }

  /// Kill the running scrcpy process.
  Future<void> kill() async {
    _process?.kill();
    await _process?.exitCode;
    _process = null;
  }

  void dispose() {
    _process?.kill();
    _process = null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/scrcpy/scrcpy_launcher_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/scrcpy/scrcpy_launcher.dart scrcpy_plus/test/scrcpy/scrcpy_launcher_test.dart
git commit -m "feat(scrcpy_plus): add ScrcpyLauncher for subprocess management"
```

---

### Task 9: Menu Builder

**Files:**
- Create: `scrcpy_plus/lib/app/menu_builder.dart`
- Create: `scrcpy_plus/test/app/menu_builder_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/app/menu_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_plus/app/menu_builder.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

void main() {
  group('MenuBuilder', () {
    test('buildMenu returns quit item', () {
      final menu = MenuBuilder.buildMenu(devices: []);
      final keys = menu.items.map((i) => i.key).toList();
      expect(keys, contains('quit'));
    });

    test('buildMenu returns pair item when no devices', () {
      final menu = MenuBuilder.buildMenu(devices: []);
      final keys = menu.items.map((i) => i.key).toList();
      expect(keys, contains('pair'));
    });

    test('buildMenu includes device items', () {
      final entry = DeviceEntry(
        info: const DeviceInfo(
          serial: 'ABCD1234',
          status: DeviceStatus.online,
          model: 'Pixel 7',
        ),
      );
      final menu = MenuBuilder.buildMenu(devices: [entry]);
      final keys = menu.items.map((i) => i.key).toList();
      expect(keys, contains('launch_ABCD1234'));
    });

    test('buildMenu includes refresh item', () {
      final menu = MenuBuilder.buildMenu(devices: []);
      final keys = menu.items.map((i) => i.key).toList();
      expect(keys, contains('refresh'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/app/menu_builder_test.dart
```

Expected: FAIL — `MenuBuilder` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/app/menu_builder.dart
import 'package:tray_manager/tray_manager.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

/// Builds the tray context menu from current app state.
class MenuBuilder {
  /// Key prefixes used for menu item identification.
  static const String launchPrefix = 'launch_';
  static const String disconnectPrefix = 'disconnect_';
  static const String infoPrefix = 'info_';

  static Menu buildMenu({required List<DeviceEntry> devices}) {
    final items = <MenuItem>[];

    if (devices.isEmpty) {
      items.add(const MenuItem(
        key: 'no_devices',
        label: 'No devices connected',
        isDisabled: true,
      ));
    } else {
      for (final device in devices) {
        items.add(MenuItem(
          key: '${launchPrefix}${device.serial}',
          label: 'Launch scrcpy: ${device.menuLabel}',
        ));
        items.add(MenuItem(
          key: '${disconnectPrefix}${device.serial}',
          label: '  Disconnect ${device.displayName}',
        ));
        if (device.detailLine != null) {
          items.add(MenuItem(
            key: '${infoPrefix}${device.serial}',
            label: '  ${device.detailLine}',
            isDisabled: true,
          ));
        }
      }
    }

    items.add(MenuItem.separator());
    items.add(const MenuItem(key: 'pair', label: 'Pair new device...'));
    items.add(const MenuItem(key: 'refresh', label: 'Refresh devices'));
    items.add(MenuItem.separator());
    items.add(const MenuItem(key: 'settings', label: 'Settings...'));
    items.add(const MenuItem(key: 'quit', label: 'Quit'));

    return Menu(items: items);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/app/menu_builder_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/app/menu_builder.dart scrcpy_plus/test/app/menu_builder_test.dart
git commit -m "feat(scrcpy_plus): add MenuBuilder for tray menu construction"
```

---

### Task 10: App Controller

**Files:**
- Create: `scrcpy_plus/lib/app/app_controller.dart`
- Create: `scrcpy_plus/test/app/app_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// scrcpy_plus/test/app/app_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/app/app_controller.dart';

void main() {
  group('AppController', () {
    test('handleMenuKey returns false for unknown key', () {
      // AppController requires real tray_manager, so we test the static helper
      expect(AppController.isLaunchAction('launch_dev1'), true);
      expect(AppController.isLaunchAction('quit'), false);
      expect(AppController.isDisconnectAction('disconnect_dev1'), true);
      expect(AppController.isDisconnectAction('quit'), false);
      expect(AppController.serialFromAction('launch_ABCD', 'launch_'), 'ABCD');
      expect(AppController.serialFromAction('disconnect_ABCD', 'disconnect_'), 'ABCD');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/app/app_controller_test.dart
```

Expected: FAIL — `AppController` not found.

- [ ] **Step 3: Write implementation**

```dart
// scrcpy_plus/lib/app/app_controller.dart
import 'dart:io';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:scrcpy_plus/app/menu_builder.dart';
import 'package:scrcpy_plus/device/device_manager.dart';
import 'package:scrcpy_plus/device/pairing_service.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_launcher.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';

/// Central controller orchestrating tray, devices, scrcpy, and settings.
class AppController implements TrayListener {
  AppController({
    required this.settingsManager,
    AdbClient? adb,
  })  : adb = adb ?? const AdbClient(),
        pairingService = PairingService(adb: adb ?? const AdbClient()) {
    deviceManager = DeviceManager(adb: this.adb);
    launcher = ScrcpyLauncher();
  }

  final SettingsManager settingsManager;
  final AdbClient adb;
  final PairingService pairingService;
  late final DeviceManager deviceManager;
  late final ScrcpyLauncher launcher;

  /// Static helpers for menu key parsing.
  static bool isLaunchAction(String key) => key.startsWith(MenuBuilder.launchPrefix);
  static bool isDisconnectAction(String key) => key.startsWith(MenuBuilder.disconnectPrefix);
  static String? serialFromAction(String key, String prefix) {
    if (!key.startsWith(prefix)) return null;
    return key.substring(prefix.length);
  }

  /// Initialize the app: load settings, start polling, set up tray.
  Future<void> init() async {
    final config = await settingsManager.loadConfig();
    launcher.config = config;

    deviceManager.addListener(_updateTrayMenu);
    await deviceManager.refresh();
    deviceManager.startPolling();

    await _initTray();
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.png');
    await trayManager.setToolTip('scrcpy_plus');
    await _updateTrayMenu();
  }

  Future<void> _updateTrayMenu() async {
    final menu = MenuBuilder.buildMenu(devices: deviceManager.devices);
    await trayManager.setContextMenu(menu);

    // Update icon based on connection state
    final icon = deviceManager.hasConnected
        ? 'assets/tray_icon_connected.png'
        : 'assets/tray_icon.png';
    await trayManager.setIcon(icon);
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;

    if (key == 'quit') {
      _quit();
    } else if (key == 'refresh') {
      deviceManager.refresh();
    } else if (key == 'pair') {
      _showPairDialog();
    } else if (key == 'settings') {
      _showSettingsDialog();
    } else if (isLaunchAction(key)) {
      final serial = serialFromAction(key, MenuBuilder.launchPrefix);
      if (serial != null) _launchScrcpy(serial);
    } else if (isDisconnectAction(key)) {
      final serial = serialFromAction(key, MenuBuilder.disconnectPrefix);
      if (serial != null) _disconnectDevice(serial);
    }
  }

  Future<void> _launchScrcpy(String serial) async {
    try {
      await launcher.launch(serial);
    } catch (e) {
      appLogger.severe('Failed to launch scrcpy: $e');
    }
  }

  Future<void> _disconnectDevice(String serial) async {
    try {
      await pairingService.disconnect(serial);
      await deviceManager.refresh();
    } catch (e) {
      appLogger.severe('Failed to disconnect $serial: $e');
    }
  }

  void _showPairDialog() {
    // TODO: Implement native dialog for IP+code input
    // For now, log a placeholder
    appLogger.info('Pair dialog not yet implemented');
  }

  void _showSettingsDialog() {
    // TODO: Implement settings dialog
    appLogger.info('Settings dialog not yet implemented');
  }

  void _quit() {
    launcher.dispose();
    deviceManager.dispose();
    trayManager.destroy();
    exit(0);
  }

  void dispose() {
    launcher.dispose();
    deviceManager.dispose();
    trayManager.removeListener(this);
  }

  // TrayListener stubs
  @override
  void onTrayIconMouseUp() {}

  @override
  void onTrayIconRightMouseDown() {}

  @override
  void onTrayIconRightMouseUp() {}
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test test/app/app_controller_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/app/app_controller.dart scrcpy_plus/test/app/app_controller_test.dart
git commit -m "feat(scrcpy_plus): add AppController orchestrating tray, devices, scrcpy"
```

---

### Task 11: Main Entry Point

**Files:**
- Modify: `scrcpy_plus/lib/main.dart`

- [ ] **Step 1: Update main.dart with full initialization**

```dart
// scrcpy_plus/lib/main.dart
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_plus/app/app_controller.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  final configDir = p.join(
    Platform.environment['HOME']!,
    'Library',
    'Application Support',
    'scrcpy_plus',
  );

  final settingsManager = SettingsManager(configDir: configDir);
  final controller = AppController(settingsManager: settingsManager);

  await controller.init();

  // Keep the app running — no window, no widget tree needed.
  // The app lives entirely in the system tray.
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter analyze lib/main.dart
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_plus/lib/main.dart
git commit -m "feat(scrcpy_plus): wire main entry point with AppController"
```

---

### Task 12: macOS Entitlements and Configuration

**Files:**
- Modify: `scrcpy_plus/macos/Runner/DebugProfile.entitlements`
- Modify: `scrcpy_plus/macos/Runner/Release.entitlements`
- Modify: `scrcpy_plus/macos/Runner/Info.plist`

- [ ] **Step 1: Update entitlements for network and process execution**

Add to both `DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

Ensure sandbox is disabled (needed for Process.start):

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

- [ ] **Step 2: Update Info.plist for LSUIElement (no dock icon)**

Add to `Info.plist` inside the `<dict>`:

```xml
<key>LSUIElement</key>
<true/>
```

This hides the app from the Dock since it's a menu-bar-only app.

- [ ] **Step 3: Verify macOS build compiles**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter build macos --debug 2>&1 | tail -5
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_plus/macos/
git commit -m "feat(scrcpy_plus): configure macOS entitlements and LSUIElement"
```

---

### Task 13: Settings Dialog

**Files:**
- Create: `scrcpy_plus/lib/settings/settings_dialog.dart`

- [ ] **Step 1: Implement native macOS settings dialog**

```dart
// scrcpy_plus/lib/settings/settings_dialog.dart
import 'dart:io';

import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';

/// Shows a simple macOS dialog for editing scrcpy settings.
/// Uses osascript for native dialog since we have no Flutter window.
class SettingsDialog {
  static Future<ScrcpyConfig?> show(ScrcpyConfig current) async {
    try {
      // Show current values and ask for new ones via osascript
      final result = await Process.run('osascript', [
        '-e',
        'display dialog "scrcpy path: ${current.scrcpyPath}\n'
            'Max size: ${current.maxSize}\n'
            'Video bit rate: ${current.videoBitRate}\n'
            'Video codec: ${current.videoCodec}" '
            'with title "scrcpy_plus Settings" '
            'buttons {"OK"} default button "OK"',
      ]);

      if (result.exitCode == 0) {
        // For MVP, just return current config unchanged.
        // A proper implementation would parse user input from the dialog.
        return current;
      }
      return null;
    } catch (e) {
      appLogger.warning('Settings dialog failed: $e');
      return null;
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter analyze lib/settings/settings_dialog.dart
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_plus/lib/settings/settings_dialog.dart
git commit -m "feat(scrcpy_plus): add SettingsDialog using osascript"
```

---

### Task 14: Pair Dialog

**Files:**
- Create: `scrcpy_plus/lib/device/pair_dialog.dart`

- [ ] **Step 1: Implement native macOS pair dialog**

```dart
// scrcpy_plus/lib/device/pair_dialog.dart
import 'dart:io';

import 'package:logger_utils/logger_utils.dart';

/// Shows a native macOS dialog for device pairing input.
class PairDialog {
  /// Show dialog for IP:port input. Returns the address or null if cancelled.
  static Future<String?> showAddressDialog() async {
    try {
      final result = await Process.run('osascript', [
        '-e',
        'display dialog "Enter device IP:port\n'
            '(e.g. 192.168.1.100:5555)" '
            'with title "Pair Device" '
            'default answer "" '
            'buttons {"Cancel", "Connect"} '
            'default button "Connect"',
      ]);

      if (result.exitCode != 0) return null;

      final output = result.stdout.toString();
      final match = RegExp(r'text returned:(.+)').firstMatch(output);
      return match?.group(1)?.trim();
    } catch (e) {
      appLogger.warning('Pair address dialog failed: $e');
      return null;
    }
  }

  /// Show dialog for pairing code input. Returns the code or null if cancelled.
  static Future<String?> showCodeDialog() async {
    try {
      final result = await Process.run('osascript', [
        '-e',
        'display dialog "Enter 6-digit pairing code\n'
            '(from phone wireless debugging)" '
            'with title "Pairing Code" '
            'default answer "" '
            'buttons {"Cancel", "Pair"} '
            'default button "Pair"',
      ]);

      if (result.exitCode != 0) return null;

      final output = result.stdout.toString();
      final match = RegExp(r'text returned:(.+)').firstMatch(output);
      return match?.group(1)?.trim();
    } catch (e) {
      appLogger.warning('Pair code dialog failed: $e');
      return null;
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter analyze lib/device/pair_dialog.dart
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_plus/lib/device/pair_dialog.dart
git commit -m "feat(scrcpy_plus): add PairDialog using osascript"
```

---

### Task 15: Wire Pair Dialog into AppController

**Files:**
- Modify: `scrcpy_plus/lib/app/app_controller.dart`

- [ ] **Step 1: Update _showPairDialog to use PairDialog**

Replace the `_showPairDialog` method in `app_controller.dart`:

```dart
  Future<void> _showPairDialog() async {
    final address = await PairDialog.showAddressDialog();
    if (address == null) return;

    final error = PairingService.validateAddress(address);
    if (error != null) {
      appLogger.warning('Invalid address: $error');
      return;
    }

    final parts = address.split(':');
    final ip = parts[0];
    final port = int.parse(parts[1]);

    // Try direct connect first (for already-paired devices)
    try {
      await pairingService.connect(ip, port);
      await deviceManager.refresh();
      return;
    } catch (_) {
      // Need pairing code
    }

    final code = await PairDialog.showCodeDialog();
    if (code == null) return;

    final codeError = PairingService.validatePairingCode(code);
    if (codeError != null) {
      appLogger.warning('Invalid code: $codeError');
      return;
    }

    try {
      await pairingService.pair(ip, port, code);
      await pairingService.connect(ip, port);
      await deviceManager.refresh();
    } catch (e) {
      appLogger.severe('Pairing failed: $e');
    }
  }
```

- [ ] **Step 2: Add import at top of file**

```dart
import 'package:scrcpy_plus/device/pair_dialog.dart';
```

- [ ] **Step 3: Verify it compiles**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter analyze lib/app/app_controller.dart
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_plus/lib/app/app_controller.dart
git commit -m "feat(scrcpy_plus): wire pair dialog into AppController"
```

---

### Task 16: Final Integration Test

**Files:**
- Create: `scrcpy_plus/test/integration/app_flow_test.dart`

- [ ] **Step 1: Write integration test for menu building flow**

```dart
// scrcpy_plus/test/integration/app_flow_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_plus/app/menu_builder.dart';
import 'package:scrcpy_plus/device/device_entry.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';
import 'dart:io';

void main() {
  group('Integration: full flow', () {
    test('menu builds correctly with mixed devices', () {
      final devices = [
        DeviceEntry(
          info: const DeviceInfo(
            serial: '192.168.1.100:5555',
            status: DeviceStatus.online,
            model: 'Pixel 7',
            androidVersion: '14',
            screenWidth: 1080,
            screenHeight: 2400,
          ),
          battery: 85,
        ),
        DeviceEntry(
          info: const DeviceInfo(
            serial: 'ABCD1234',
            status: DeviceStatus.online,
            model: 'Samsung S23',
          ),
        ),
      ];

      final menu = MenuBuilder.buildMenu(devices: devices);
      final keys = menu.items.map((i) => i.key).toList();

      // Should have launch items for both devices
      expect(keys, contains('launch_192.168.1.100:5555'));
      expect(keys, contains('launch_ABCD1234'));
      // Should have disconnect items
      expect(keys, contains('disconnect_192.168.1.100:5555'));
      expect(keys, contains('disconnect_ABCD1234'));
      // Should have standard items
      expect(keys, contains('pair'));
      expect(keys, contains('refresh'));
      expect(keys, contains('settings'));
      expect(keys, contains('quit'));
    });

    test('scrcpy config produces valid args', () {
      const config = ScrcpyConfig(
        maxSize: 1280,
        videoBitRate: '4M',
        videoCodec: 'h265',
      );
      final args = config.toArgs('Pixel7');

      expect(args.first, '--serial');
      expect(args[1], 'Pixel7');
      expect(args, contains('--max-size'));
      expect(args, contains('1280'));
    });

    test('settings round-trip preserves all fields', () async {
      final tempDir = await Directory.systemTemp.createTemp('scrcpy_plus_integ_');
      try {
        final manager = SettingsManager(configDir: tempDir.path);
        const config = ScrcpyConfig(
          scrcpyPath: '/opt/homebrew/bin/scrcpy',
          maxSize: 1920,
          videoBitRate: '12M',
          videoCodec: 'h265',
        );

        await manager.saveConfig(config);
        await manager.saveKnownSerials(['dev1', 'dev2', 'dev3']);

        final loaded = await manager.loadConfig();
        final serials = await manager.loadKnownSerials();

        expect(loaded.scrcpyPath, '/opt/homebrew/bin/scrcpy');
        expect(loaded.maxSize, 1920);
        expect(loaded.videoBitRate, '12M');
        expect(loaded.videoCodec, 'h265');
        expect(serials, ['dev1', 'dev2', 'dev3']);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
```

- [ ] **Step 2: Run all tests**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter test
```

Expected: All tests PASS.

- [ ] **Step 3: Run full workspace analysis**

```bash
cd /Users/hao/ai/mobile/asf_dev
melos run analyze
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_plus/test/integration/app_flow_test.dart
git commit -m "test(scrcpy_plus): add integration tests for full flow"
```

---

### Task 17: Run and Verify

- [ ] **Step 1: Run the app**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_plus
flutter run -d macos
```

Expected: App starts, appears in system tray, no dock icon.

- [ ] **Step 2: Verify tray menu**

Click the tray icon. Expected menu:
- No devices connected (disabled text)
- Pair new device...
- Refresh devices
- Settings...
- Quit

- [ ] **Step 3: Test with real device**

If a device is connected via USB:
- Click "Refresh devices"
- Device should appear in menu
- Click "Launch scrcpy" → scrcpy window opens

- [ ] **Step 4: Final commit**

```bash
git add -A scrcpy_plus/
git commit -m "feat(scrcpy_plus): complete MVP — menu-bar Android device manager"
```
