# Device Info Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Android device model name, manufacturer, Android version, connection type, and status on each device card in `DevicesPage` instead of raw serial IDs.

**Architecture:** Add `DeviceInfo` model + `getDevicesWithInfo()` to `packages/autoglm_adb`; add a new Riverpod provider `adbDevicesWithInfoProvider` in `autoglm_app`; rewrite the device card widget in `DevicesPage` to render rich info. Existing `getDevices()` is untouched so `scrcpy_view` and other callers are unaffected.

**Tech Stack:** Dart, Flutter, `flutter_riverpod ^2.5.1`, `flutter_test` SDK, mocked `AdbProcessRunner`.

---

## File Map

| File | Action |
|---|---|
| `packages/autoglm_adb/lib/src/device_info.dart` | Create — `DeviceInfo` class + `DeviceStatus` enum |
| `packages/autoglm_adb/lib/src/adb_client.dart` | Add `getDevicesWithInfo()` + private `_parseGetprop()` |
| `packages/autoglm_adb/lib/autoglm_adb.dart` | Export `device_info.dart` |
| `packages/autoglm_adb/test/device_info_test.dart` | Create — unit tests for parsing logic |
| `autoglm_app/lib/providers/adb_provider.dart` | Add `adbDevicesWithInfoProvider` |
| `autoglm_app/lib/pages/devices_page.dart` | Switch provider + rewrite card as `_DeviceCard` + `_StatusBadge` |
| `autoglm_app/test/devices_page_test.dart` | Create — widget tests for all three status states |

---

## Task 1: `DeviceInfo` model

**Files:**
- Create: `packages/autoglm_adb/lib/src/device_info.dart`
- Modify: `packages/autoglm_adb/lib/autoglm_adb.dart`

- [ ] **Step 1: Create `device_info.dart`**

  Create `packages/autoglm_adb/lib/src/device_info.dart`:

  ```dart
  /// Connection and identification state of a single ADB device.
  enum DeviceStatus { online, offline, unauthorized }

  /// Rich device info gathered from `adb devices` + `adb shell getprop`.
  class DeviceInfo {
    const DeviceInfo({
      required this.serial,
      required this.status,
      this.model,
      this.manufacturer,
      this.androidVersion,
      this.sdkVersion,
    });

    final String serial;
    final DeviceStatus status;
    final String? model;          // ro.product.model
    final String? manufacturer;   // ro.product.manufacturer
    final String? androidVersion; // ro.build.version.release
    final int? sdkVersion;        // ro.build.version.sdk

    /// True when the serial contains ':' (wireless ADB address:port format).
    bool get isWifi => serial.contains(':');

    /// Human-readable title: model name if available, serial otherwise.
    String get displayName => model ?? serial;
  }
  ```

- [ ] **Step 2: Export from barrel**

  In `packages/autoglm_adb/lib/autoglm_adb.dart`, add the export after the existing exports:

  ```dart
  /// ADB client and binary management for AutoGLM.
  library;

  export 'src/adb_binary_manager.dart';
  export 'src/adb_client.dart';
  export 'src/adb_process_runner.dart';
  export 'src/device_info.dart';
  export 'src/exceptions.dart';
  ```

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter
  git add packages/autoglm_adb/lib/src/device_info.dart \
           packages/autoglm_adb/lib/autoglm_adb.dart
  git commit -m "feat(autoglm_adb): add DeviceInfo model and DeviceStatus enum"
  ```

---

## Task 2: `getDevicesWithInfo()` in `AdbClient`

**Files:**
- Modify: `packages/autoglm_adb/lib/src/adb_client.dart`
- Create: `packages/autoglm_adb/test/device_info_test.dart`

- [ ] **Step 1: Write failing tests**

  Create `packages/autoglm_adb/test/device_info_test.dart`:

  ```dart
  import 'dart:io';

  import 'package:autoglm_adb/src/adb_client.dart';
  import 'package:autoglm_adb/src/adb_process_runner.dart';
  import 'package:autoglm_adb/src/device_info.dart';
  import 'package:autoglm_adb/src/exceptions.dart';
  import 'package:flutter_test/flutter_test.dart';

  // ---------------------------------------------------------------------------
  // Fake runner: maps "arg0 arg1 ..." → stdout string
  // ---------------------------------------------------------------------------

  class _MapRunner extends AdbProcessRunner {
    _MapRunner(this._map, {this.throwOn});
    final Map<String, String> _map;
    final String? throwOn; // argument substring that triggers throw

    @override
    Future<ProcessResult> runRaw(
      String executable,
      List<String> arguments, {
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final key = arguments.join(' ');
      if (throwOn != null && key.contains(throwOn!)) {
        throw const AdbException('Command failed');
      }
      return ProcessResult(0, 0, _map[key] ?? '', '');
    }
  }

  const _devicesHeader = 'List of devices attached\n';

  const _sampleGetprop = '''
  [ro.product.model]: [Pixel 8 Pro]
  [ro.product.manufacturer]: [Google]
  [ro.build.version.release]: [14]
  [ro.build.version.sdk]: [34]
  [some.other.prop]: [value]
  ''';

  void main() {
    group('AdbClient.getDevicesWithInfo', () {
      test('returns online device with model info', () async {
        final client = AdbClient(
          runner: _MapRunner({
            'devices': '${_devicesHeader}R3CN12345\tdevice\n',
            '-s R3CN12345 shell getprop': _sampleGetprop,
          }),
        );

        final devices = await client.getDevicesWithInfo();

        expect(devices, hasLength(1));
        final d = devices.first;
        expect(d.serial, 'R3CN12345');
        expect(d.status, DeviceStatus.online);
        expect(d.model, 'Pixel 8 Pro');
        expect(d.manufacturer, 'Google');
        expect(d.androidVersion, '14');
        expect(d.sdkVersion, 34);
        expect(d.isWifi, isFalse);
        expect(d.displayName, 'Pixel 8 Pro');
      });

      test('Wi-Fi serial sets isWifi true', () async {
        final client = AdbClient(
          runner: _MapRunner({
            'devices': '${_devicesHeader}192.168.1.5:5555\tdevice\n',
            '-s 192.168.1.5:5555 shell getprop': _sampleGetprop,
          }),
        );

        final devices = await client.getDevicesWithInfo();
        expect(devices.first.isWifi, isTrue);
      });

      test('offline device skips getprop, info fields are null', () async {
        final client = AdbClient(
          runner: _MapRunner({
            'devices': '${_devicesHeader}emulator-5554\toffline\n',
          }),
        );

        final devices = await client.getDevicesWithInfo();

        expect(devices, hasLength(1));
        final d = devices.first;
        expect(d.status, DeviceStatus.offline);
        expect(d.model, isNull);
        expect(d.manufacturer, isNull);
        expect(d.androidVersion, isNull);
        expect(d.sdkVersion, isNull);
      });

      test('unauthorized device skips getprop', () async {
        final client = AdbClient(
          runner: _MapRunner({
            'devices': '${_devicesHeader}192.168.1.8:5555\tunauthorized\n',
          }),
        );

        final devices = await client.getDevicesWithInfo();
        final d = devices.first;
        expect(d.status, DeviceStatus.unauthorized);
        expect(d.model, isNull);
      });

      test('getprop exception degrades gracefully', () async {
        final client = AdbClient(
          runner: _MapRunner(
            {'devices': '${_devicesHeader}R3CN12345\tdevice\n'},
            throwOn: 'getprop',
          ),
        );

        final devices = await client.getDevicesWithInfo();

        expect(devices, hasLength(1));
        final d = devices.first;
        expect(d.status, DeviceStatus.online);
        expect(d.model, isNull);
        expect(d.displayName, 'R3CN12345'); // falls back to serial
      });

      test('mixes online and offline devices', () async {
        final client = AdbClient(
          runner: _MapRunner({
            'devices':
                '${_devicesHeader}R3CN12345\tdevice\nemulator-5554\toffline\n',
            '-s R3CN12345 shell getprop': _sampleGetprop,
          }),
        );

        final devices = await client.getDevicesWithInfo();

        expect(devices, hasLength(2));
        expect(
          devices.firstWhere((d) => d.serial == 'R3CN12345').model,
          'Pixel 8 Pro',
        );
        expect(
          devices.firstWhere((d) => d.serial == 'emulator-5554').model,
          isNull,
        );
      });

      test('empty device list returns empty', () async {
        final client = AdbClient(
          runner: _MapRunner({'devices': _devicesHeader}),
        );
        final devices = await client.getDevicesWithInfo();
        expect(devices, isEmpty);
      });
    });
  }
  ```

- [ ] **Step 2: Run tests — expect compile failure**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter
  flutter test packages/autoglm_adb/test/device_info_test.dart 2>&1 | tail -5
  ```

  Expected: error — `getDevicesWithInfo` not found on `AdbClient`.

- [ ] **Step 3: Implement `getDevicesWithInfo()` in `AdbClient`**

  Open `packages/autoglm_adb/lib/src/adb_client.dart`.

  Add this import at the top (after existing imports):

  ```dart
  import 'package:autoglm_adb/src/device_info.dart';
  ```

  Add these two methods at the end of the `AdbClient` class, before the closing `}`:

  ```dart
    /// Returns detailed info for all currently attached devices.
    ///
    /// Calls `adb devices` for serial + status, then concurrently runs
    /// `adb shell getprop` for each online device. Offline and unauthorized
    /// devices return null info fields. Any getprop failure also returns null
    /// fields — the device is still included in the result.
    Future<List<DeviceInfo>> getDevicesWithInfo() async {
      final result = await runner.runRaw(adbPath, ['devices']);
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
            final propResult = await runner.runRaw(
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
  ```

- [ ] **Step 4: Run tests — expect pass**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter
  flutter test packages/autoglm_adb/test/device_info_test.dart --reporter=expanded 2>&1 | tail -15
  ```

  Expected: `+7: All tests passed!`

- [ ] **Step 5: Run full autoglm_adb test suite**

  ```bash
  flutter test packages/autoglm_adb/ --reporter=expanded 2>&1 | tail -10
  ```

  Expected: all tests pass (existing tests still green).

- [ ] **Step 6: Commit**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter
  git add packages/autoglm_adb/lib/src/adb_client.dart \
           packages/autoglm_adb/test/device_info_test.dart
  git commit -m "feat(autoglm_adb): add getDevicesWithInfo() with parallel getprop fetching"
  ```

---

## Task 3: Riverpod provider + DevicesPage UI

**Files:**
- Modify: `autoglm_app/lib/providers/adb_provider.dart`
- Modify: `autoglm_app/lib/pages/devices_page.dart`
- Create: `autoglm_app/test/devices_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

  Create `autoglm_app/test/devices_page_test.dart`:

  ```dart
  import 'package:autoglm_adb/autoglm_adb.dart';
  import 'package:autoglm_app/i18n/strings.g.dart';
  import 'package:autoglm_app/pages/devices_page.dart';
  import 'package:autoglm_app/providers/adb_provider.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';

  Widget _wrap(List<DeviceInfo> devices) {
    return ProviderScope(
      overrides: [
        adbDevicesWithInfoProvider.overrideWith((_) async => devices),
      ],
      child: TranslationProvider(
        child: const MaterialApp(home: DevicesPage()),
      ),
    );
  }

  void main() {
    setUpAll(LocaleSettings.useDeviceLocale);

    testWidgets('shows model name and online badge for online device',
        (tester) async {
      await tester.pumpWidget(
        _wrap([
          const DeviceInfo(
            serial: 'R3CN12345',
            status: DeviceStatus.online,
            model: 'Pixel 8 Pro',
            manufacturer: 'Google',
            androidVersion: '14',
            sdkVersion: 34,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pixel 8 Pro'), findsOneWidget);
      expect(find.text('online'), findsOneWidget);
      expect(find.text('offline'), findsNothing);
    });

    testWidgets('shows serial as title when model is null (offline device)',
        (tester) async {
      await tester.pumpWidget(
        _wrap([
          const DeviceInfo(
            serial: 'emulator-5554',
            status: DeviceStatus.offline,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('emulator-5554'), findsWidgets); // title + serial row
      expect(find.text('offline'), findsOneWidget);
    });

    testWidgets('shows unauthorized badge for unauthorized device',
        (tester) async {
      await tester.pumpWidget(
        _wrap([
          const DeviceInfo(
            serial: '192.168.1.8:5555',
            status: DeviceStatus.unauthorized,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('unauthorized'), findsOneWidget);
    });

    testWidgets('shows no-device message when list is empty', (tester) async {
      await tester.pumpWidget(_wrap([]));
      await tester.pumpAndSettle();

      expect(find.text(t.devices_page.no_devices), findsOneWidget);
    });

    testWidgets('shows Wi-Fi icon for wireless serial', (tester) async {
      await tester.pumpWidget(
        _wrap([
          const DeviceInfo(
            serial: '192.168.1.5:5555',
            status: DeviceStatus.online,
            model: 'Xiaomi 14',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.wifi), findsOneWidget);
      expect(find.byIcon(Icons.usb), findsNothing);
    });

    testWidgets('shows USB icon for wired serial', (tester) async {
      await tester.pumpWidget(
        _wrap([
          const DeviceInfo(
            serial: 'R3CN12345',
            status: DeviceStatus.online,
            model: 'Pixel 8',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.usb), findsOneWidget);
      expect(find.byIcon(Icons.wifi), findsNothing);
    });
  }
  ```

- [ ] **Step 2: Run tests — expect compile failure**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter/autoglm_app
  flutter test test/devices_page_test.dart 2>&1 | tail -5
  ```

  Expected: error — `adbDevicesWithInfoProvider` not found.

- [ ] **Step 3: Add `adbDevicesWithInfoProvider` to `adb_provider.dart`**

  Open `autoglm_app/lib/providers/adb_provider.dart`. Add this import and provider after the existing `adbDevicesProvider`:

  ```dart
  import 'package:autoglm_adb/autoglm_adb.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:path/path.dart' as p;
  import 'package:path_provider/path_provider.dart';

  /// Provider for the [AdbBinaryManager].
  final adbBinaryManagerProvider = Provider<Future<AdbBinaryManager>>((
    ref,
  ) async {
    final appSupportDir = await getApplicationSupportDirectory();
    final binDir = p.join(appSupportDir.path, 'bin');
    return AdbBinaryManager(binDir: binDir);
  });

  /// Provider for the [AdbClient].
  final adbClientProvider = FutureProvider<AdbClient>((ref) async {
    final manager = await ref.watch(adbBinaryManagerProvider);
    final adbPath = await manager.ensureAdb();
    return AdbClient(adbPath: adbPath);
  });

  /// Provider for the list of connected ADB devices (serial IDs only).
  final adbDevicesProvider = FutureProvider.autoDispose<List<String>>((
    ref,
  ) async {
    final client = await ref.watch(adbClientProvider.future);
    return client.getDevices();
  });

  /// Provider for the list of connected devices with rich info.
  final adbDevicesWithInfoProvider =
      FutureProvider.autoDispose<List<DeviceInfo>>((ref) async {
    final client = await ref.watch(adbClientProvider.future);
    return client.getDevicesWithInfo();
  });
  ```

- [ ] **Step 4: Rewrite `devices_page.dart`**

  Replace the entire contents of `autoglm_app/lib/pages/devices_page.dart`:

  ```dart
  import 'package:autoglm_adb/autoglm_adb.dart';
  import 'package:autoglm_app/i18n/strings.g.dart';
  import 'package:autoglm_app/providers/adb_provider.dart';
  import 'package:autoglm_app/providers/device_provider.dart';
  import 'package:autoglm_app/theme/design_tokens.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  /// Page for managing connected ADB devices.
  class DevicesPage extends ConsumerWidget {
    /// Creates a [DevicesPage].
    const DevicesPage({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final devicesAsync = ref.watch(adbDevicesWithInfoProvider);
      final selectedId = ref.watch(selectedDeviceIdProvider);
      final theme = Theme.of(context);

      return Scaffold(
        appBar: AppBar(
          title: Text(t.nav.devices),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: t.devices_page.refresh,
              onPressed: () => ref.invalidate(adbDevicesWithInfoProvider),
            ),
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: t.devices_page.pair_device,
              onPressed: () => _showPairDialog(context, ref),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        body: devicesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48,
                    color: theme.colorScheme.error),
                const SizedBox(height: AppSpacing.md),
                Text('Error: $e'),
              ],
            ),
          ),
          data: (devices) {
            if (devices.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.devices_other, size: 64,
                        color: theme.colorScheme.outline),
                    const SizedBox(height: AppSpacing.md),
                    Text(t.devices_page.no_devices,
                        style: theme.textTheme.titleMedium),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: AppSpacing.edgeInsetsMd,
              itemCount: devices.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, index) {
                final info = devices[index];
                return _DeviceCard(
                  info: info,
                  isSelected: info.serial == selectedId,
                  onTap: () => ref
                      .read(selectedDeviceIdProvider.notifier)
                      .state = info.serial,
                );
              },
            );
          },
        ),
      );
    }

    void _showPairDialog(BuildContext context, WidgetRef ref) {
      final ipCtrl = TextEditingController();
      final portCtrl = TextEditingController();
      final codeCtrl = TextEditingController();

      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.devices_page.pair_device),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderLg),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ipCtrl,
                decoration: InputDecoration(
                  labelText: t.devices_page.ip,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.network_wifi),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t.devices_page.port,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: codeCtrl,
                decoration: InputDecoration(
                  labelText: t.devices_page.code,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final port = int.tryParse(portCtrl.text) ?? 0;
                try {
                  final client = await ref.read(adbClientProvider.future);
                  final res =
                      await client.pair(ipCtrl.text, port, codeCtrl.text);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text(res)));
                    ref.invalidate(adbDevicesWithInfoProvider);
                  }
                } on Exception catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Pair'),
            ),
          ],
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Private widgets
  // ---------------------------------------------------------------------------

  class _DeviceCard extends StatelessWidget {
    const _DeviceCard({
      required this.info,
      required this.isSelected,
      required this.onTap,
    });

    final DeviceInfo info;
    final bool isSelected;
    final VoidCallback onTap;

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      return Card(
        elevation: isSelected ? 2 : 0,
        color: isSelected
            ? theme.colorScheme.primaryContainer.withOpacity(0.3)
            : theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderMd,
          side: isSelected
              ? BorderSide(color: theme.colorScheme.primary, width: 2)
              : BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          leading: CircleAvatar(
            backgroundColor: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceVariant,
            child: Icon(
              Icons.smartphone,
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text(
            info.displayName,
            style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : null),
          ),
          subtitle: _CardSubtitle(info: info),
          trailing: _StatusBadge(status: info.status),
          onTap: onTap,
        ),
      );
    }
  }

  class _CardSubtitle extends StatelessWidget {
    const _CardSubtitle({required this.info});
    final DeviceInfo info;

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final hasDetails =
          info.manufacturer != null || info.androidVersion != null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasDetails)
            Text(_detailLine(), style: theme.textTheme.bodySmall),
          Row(
            children: [
              Flexible(
                child: Text(
                  info.serial,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                info.isWifi ? Icons.wifi : Icons.usb,
                size: 14,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ],
      );
    }

    String _detailLine() {
      final parts = <String>[];
      if (info.manufacturer != null) parts.add(info.manufacturer!);
      if (info.androidVersion != null) {
        final sdk =
            info.sdkVersion != null ? ' (API ${info.sdkVersion})' : '';
        parts.add('Android ${info.androidVersion}$sdk');
      }
      return parts.join(' · ');
    }
  }

  class _StatusBadge extends StatelessWidget {
    const _StatusBadge({required this.status});
    final DeviceStatus status;

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      return switch (status) {
        DeviceStatus.online => _badge(
            theme, Icons.circle, 10, theme.colorScheme.primary, 'online'),
        DeviceStatus.offline => _badge(
            theme, Icons.circle_outlined, 10, theme.colorScheme.outline,
            'offline'),
        DeviceStatus.unauthorized => _badge(
            theme, Icons.warning_amber, 14, theme.colorScheme.error,
            'unauthorized'),
      };
    }

    Widget _badge(ThemeData t, IconData icon, double size, Color color,
        String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: size, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: color)),
        ],
      );
    }
  }
  ```

- [ ] **Step 5: Run widget tests — expect pass**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter/autoglm_app
  flutter test test/devices_page_test.dart --reporter=expanded 2>&1 | tail -15
  ```

  Expected: `+6: All tests passed!`

- [ ] **Step 6: Run full autoglm_app test suite**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter/autoglm_app
  flutter test --reporter=expanded 2>&1 | tail -10
  ```

  Expected: all tests pass.

- [ ] **Step 7: Verify analyze is clean for changed packages**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter
  dart analyze packages/autoglm_adb autoglm_app 2>&1 | grep -E "^.*error\b" | head -20
  ```

  Expected: no output (no errors).

- [ ] **Step 8: Commit**

  ```bash
  cd /Users/hao/ai/mobile/autoglm_scrcpy_flutter
  git add autoglm_app/lib/providers/adb_provider.dart \
           autoglm_app/lib/pages/devices_page.dart \
           autoglm_app/test/devices_page_test.dart
  git commit -m "feat(autoglm_app): show device model, manufacturer, Android version and status in DevicesPage"
  ```
