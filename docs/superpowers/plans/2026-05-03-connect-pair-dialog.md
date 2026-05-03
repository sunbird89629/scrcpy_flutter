# Connect/Pair Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the minimal `_showPairDialog` in `DevicesPage` with a polished `_ConnectPairDialog` ConsumerStatefulWidget that handles both reconnect and first-time pairing in a single progressive flow.

**Architecture:** Private `ConsumerStatefulWidget` in `devices_page.dart`, managing `_DialogStep` enum (connect → pair). Step 1 collects IP+port and calls `connect()`; on failure, Step 2 reveals a pair-code field and calls `pair()` then auto-`connect()`. Validation and operation errors surface as Snackbars; the dialog stays open until success.

**Tech Stack:** Flutter ConsumerStatefulWidget, Riverpod `adbClientProvider` / `adbDevicesWithInfoProvider`, slang i18n, `showDialog`.

---

## File Map

| File | Action |
|---|---|
| `autoglm_app/lib/i18n/en-US.i18n.json` | Add 15 keys under `devices_page` |
| `autoglm_app/lib/i18n/zh-CN.i18n.json` | Add 15 keys (Chinese) |
| `autoglm_app/lib/i18n/strings.g.dart` | Regenerated — do not edit manually |
| `autoglm_app/lib/pages/devices_page.dart` | Add `_DialogStep` enum + `_ConnectPairDialog`; remove `_showPairDialog`; wire toolbar button |
| `autoglm_app/test/devices_page_test.dart` | Add `_FakeAdbClient` helper + 8 dialog tests |

---

## Task 1: i18n keys

**Files:**
- Modify: `autoglm_app/lib/i18n/en-US.i18n.json`
- Modify: `autoglm_app/lib/i18n/zh-CN.i18n.json`
- Regenerate: `autoglm_app/lib/i18n/strings.g.dart` (via codegen)

- [ ] **Step 1: Add 15 keys to `en-US.i18n.json`**

  Replace the existing `devices_page` block (currently ends at `"code": "Pairing Code (6 digits)"`) with:

  ```json
  "devices_page": {
    "title": "Connected Devices",
    "refresh": "Refresh",
    "no_devices": "No devices connected.",
    "pair_device": "Pair Device",
    "ip": "IP Address",
    "port": "Port",
    "code": "Pairing Code (6 digits)",
    "connect_device": "Connect Device",
    "connect": "Connect",
    "connecting": "Connecting...",
    "not_paired_hint": "Device not paired. Enter the pairing code from Wireless Debugging.",
    "pair": "Pair",
    "pairing": "Pairing...",
    "back": "Back",
    "connected_to": "Connected to {serial}",
    "paired_and_connected": "Paired and connected to {serial}",
    "invalid_ip": "Invalid IP address",
    "invalid_port": "Port must be between 1 and 65535",
    "invalid_code": "Pairing code must be 6 digits",
    "connection_refused": "Connection refused. Make sure Wireless Debugging is enabled on the device.",
    "invalid_pairing_code": "Invalid pairing code. Get a new one from Wireless Debugging.",
    "already_connected": "Device already connected."
  }
  ```

- [ ] **Step 2: Add 15 keys to `zh-CN.i18n.json`**

  Replace the existing `devices_page` block with:

  ```json
  "devices_page": {
    "title": "已连接设备",
    "refresh": "刷新",
    "no_devices": "没有已连接的设备",
    "pair_device": "无线配对",
    "ip": "IP 地址",
    "port": "端口",
    "code": "配对码 (6位)",
    "connect_device": "连接设备",
    "connect": "连接",
    "connecting": "连接中…",
    "not_paired_hint": "设备未配对，请从手机「无线调试」获取配对码",
    "pair": "配对",
    "pairing": "配对中…",
    "back": "返回",
    "connected_to": "已连接到 {serial}",
    "paired_and_connected": "已配对并连接到 {serial}",
    "invalid_ip": "IP 地址格式无效",
    "invalid_port": "端口必须在 1–65535 之间",
    "invalid_code": "配对码必须是 6 位数字",
    "connection_refused": "连接被拒绝，请确认手机上已开启无线调试",
    "invalid_pairing_code": "配对码无效，请在手机上重新获取",
    "already_connected": "设备已连接"
  }
  ```

- [ ] **Step 3: Regenerate i18n**

  Run from the repo root:
  ```bash
  melos run gen:i18n
  ```

  Expected: `autoglm_app/lib/i18n/strings.g.dart` and associated `.g.dart` files are regenerated with 38 keys per locale. No errors.

- [ ] **Step 4: Verify no analysis errors**

  ```bash
  cd autoglm_app && flutter analyze --no-fatal-infos
  ```

  Expected: No errors or warnings.

- [ ] **Step 5: Commit**

  ```bash
  git add autoglm_app/lib/i18n/
  git commit -m "feat(autoglm_app): add i18n keys for connect/pair dialog"
  ```

---

## Task 2: `_ConnectPairDialog` widget (TDD)

**Files:**
- Modify: `autoglm_app/test/devices_page_test.dart`
- Modify: `autoglm_app/lib/pages/devices_page.dart`

### Step 1 — Write the failing tests

- [ ] **Step 1a: Update `_wrap` helper and add `_FakeAdbClient` to `devices_page_test.dart`**

  Add `import 'dart:collection';` and `import 'package:autoglm_adb/autoglm_adb.dart';` if not already present (both are already imported). Add after the existing imports:

  ```dart
  import 'dart:collection';
  ```

  Then replace the `_wrap` function and add `_FakeAdbClient` **before** `void main()`:

  ```dart
  Widget _wrap(List<DeviceInfo> devices, {AdbClient? adbClient}) {
    return ProviderScope(
      overrides: [
        adbDevicesWithInfoProvider.overrideWith((_) async => devices),
        if (adbClient != null)
          adbClientProvider.overrideWith((_) async => adbClient),
      ],
      child: TranslationProvider(
        child: const MaterialApp(home: DevicesPage()),
      ),
    );
  }

  class _FakeAdbClient extends AdbClient {
    _FakeAdbClient({
      List<Object>? connectResponses,
      List<Object>? pairResponses,
    })  : _connectQ = Queue.of(connectResponses ?? []),
          _pairQ = Queue.of(pairResponses ?? []);

    final Queue<Object> _connectQ;
    final Queue<Object> _pairQ;

    @override
    Future<String> connect(String ip, int port) async {
      final r = _connectQ.isNotEmpty ? _connectQ.removeFirst() : 'connected to $ip:$port';
      if (r is AdbException) throw r;
      return r as String;
    }

    @override
    Future<String> pair(String ip, int port, String code) async {
      final r = _pairQ.isNotEmpty ? _pairQ.removeFirst() : 'Successfully paired to $ip:$port';
      if (r is AdbException) throw r;
      return r as String;
    }

    @override
    Future<List<DeviceInfo>> getDevicesWithInfo() async => [];
  }
  ```

- [ ] **Step 1b: Add dialog tests to `devices_page_test.dart`**

  Add a new `group('_ConnectPairDialog', ...)` block inside `void main()`, after the existing 6 device-card tests:

  ```dart
  group('_ConnectPairDialog', () {
    Future<void> openDialog(WidgetTester tester, {AdbClient? adbClient}) async {
      await tester.pumpWidget(_wrap([], adbClient: adbClient));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_link));
      await tester.pumpAndSettle();
    }

    testWidgets('shows IP and port fields but no code field initially',
        (tester) async {
      await openDialog(tester);
      expect(find.byKey(const Key('code_field')), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('connect success closes dialog and shows Snackbar',
        (tester) async {
      final client = _FakeAdbClient(
        connectResponses: ['connected to 192.168.1.1:5555'],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('192.168.1.1:5555'), findsOneWidget);
    });

    testWidgets('connect failure reveals code field', (tester) async {
      final client = _FakeAdbClient(
        connectResponses: [
          const AdbException('Connect failed: not paired'),
        ],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('code_field')), findsOneWidget);
    });

    testWidgets('empty IP shows invalid_ip Snackbar', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      expect(find.text(t.devices_page.invalid_ip), findsOneWidget);
    });

    testWidgets('port 0 shows invalid_port Snackbar', (tester) async {
      await openDialog(tester);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '0');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      expect(find.text(t.devices_page.invalid_port), findsOneWidget);
    });

    testWidgets('5-digit code shows invalid_code Snackbar', (tester) async {
      final client = _FakeAdbClient(
        connectResponses: [
          const AdbException('Connect failed: not paired'),
        ],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      // Now in Step 2 — enter 5-digit code
      await tester.enterText(find.byKey(const Key('code_field')), '12345');
      await tester.tap(find.text(t.devices_page.pair));
      await tester.pumpAndSettle();
      expect(find.text(t.devices_page.invalid_code), findsOneWidget);
    });

    testWidgets('pair success closes dialog and shows paired_and_connected',
        (tester) async {
      final client = _FakeAdbClient(
        connectResponses: [
          const AdbException('Connect failed: not paired'), // Step 1 fails
          'connected to 192.168.1.1:5555', // auto-connect after pair
        ],
        pairResponses: ['Successfully paired to 192.168.1.1:5555'],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('code_field')), '123456');
      await tester.tap(find.text(t.devices_page.pair));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('192.168.1.1:5555'), findsOneWidget);
    });

    testWidgets('pair failure keeps dialog open and shows error Snackbar',
        (tester) async {
      final client = _FakeAdbClient(
        connectResponses: [
          const AdbException('Connect failed: not paired'),
        ],
        pairResponses: [
          const AdbException('Invalid pairing code'),
        ],
      );
      await openDialog(tester, adbClient: client);
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.ip), '192.168.1.1');
      await tester.enterText(
          find.widgetWithText(TextField, t.devices_page.port), '5555');
      await tester.tap(find.text(t.devices_page.connect));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('code_field')), '123456');
      await tester.tap(find.text(t.devices_page.pair));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(t.devices_page.invalid_pairing_code), findsOneWidget);
    });
  });
  ```

- [ ] **Step 2: Add stub to `devices_page.dart` so tests compile**

  Append the following before the closing brace of the file (after `_StatusBadge`). This makes the test file compile — tests will fail with assertion errors, not compile errors:

  ```dart
  // ---------------------------------------------------------------------------
  // Connect / Pair dialog
  // ---------------------------------------------------------------------------

  enum _DialogStep { connect, pair }

  class _ConnectPairDialog extends ConsumerStatefulWidget {
    const _ConnectPairDialog();

    @override
    ConsumerState<_ConnectPairDialog> createState() =>
        _ConnectPairDialogState();
  }

  class _ConnectPairDialogState extends ConsumerState<_ConnectPairDialog> {
    @override
    Widget build(BuildContext context) =>
        const AlertDialog(title: Text('TODO'));
  }
  ```

- [ ] **Step 3: Run tests — verify they fail**

  ```bash
  cd autoglm_app && flutter test test/devices_page_test.dart --no-pub 2>&1 | tail -30
  ```

  Expected: Tests compile but the dialog-group tests fail (e.g., `Expected: exactly one matching node`). The 6 existing device-card tests should still pass.

- [ ] **Step 4: Implement full `_ConnectPairDialog`**

  Replace the stub `_ConnectPairDialogState.build` and add the full state in `devices_page.dart`. The complete class block (replacing everything from `enum _DialogStep` to the end of file):

  ```dart
  // ---------------------------------------------------------------------------
  // Connect / Pair dialog
  // ---------------------------------------------------------------------------

  enum _DialogStep { connect, pair }

  class _ConnectPairDialog extends ConsumerStatefulWidget {
    const _ConnectPairDialog();

    @override
    ConsumerState<_ConnectPairDialog> createState() =>
        _ConnectPairDialogState();
  }

  class _ConnectPairDialogState extends ConsumerState<_ConnectPairDialog> {
    _DialogStep _step = _DialogStep.connect;
    bool _isLoading = false;

    final _ipCtrl = TextEditingController();
    final _portCtrl = TextEditingController();
    final _codeCtrl = TextEditingController();

    @override
    void dispose() {
      _ipCtrl.dispose();
      _portCtrl.dispose();
      _codeCtrl.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(t.devices_page.connect_device),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderLg),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_step == _DialogStep.pair)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  t.devices_page.not_paired_hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            TextField(
              controller: _ipCtrl,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: t.devices_page.ip,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.network_wifi),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _portCtrl,
              enabled: !_isLoading,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.devices_page.port,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.numbers),
              ),
            ),
            if (_step == _DialogStep.pair) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('code_field'),
                controller: _codeCtrl,
                enabled: !_isLoading,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t.devices_page.code,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: CircularProgressIndicator(),
            )
          else ...[
            if (_step == _DialogStep.pair)
              TextButton(
                onPressed: () => setState(() {
                  _step = _DialogStep.connect;
                  _codeCtrl.clear();
                }),
                child: Text(t.devices_page.back),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            FilledButton(
              onPressed:
                  _step == _DialogStep.connect ? _onConnect : _onPair,
              child: Text(_step == _DialogStep.connect
                  ? t.devices_page.connect
                  : t.devices_page.pair),
            ),
          ],
        ],
      );
    }

    bool _validate() {
      final ip = _ipCtrl.text.trim();
      final port = _portCtrl.text.trim();

      if (ip.isEmpty ||
          !RegExp(r'^[\d.]+$').hasMatch(ip) ||
          '.'.allMatches(ip).length < 2) {
        _showSnackbar(t.devices_page.invalid_ip);
        return false;
      }

      final portNum = int.tryParse(port);
      if (portNum == null || portNum < 1 || portNum > 65535) {
        _showSnackbar(t.devices_page.invalid_port);
        return false;
      }

      if (_step == _DialogStep.pair) {
        final code = _codeCtrl.text.trim();
        if (code.length != 6 || int.tryParse(code) == null) {
          _showSnackbar(t.devices_page.invalid_code);
          return false;
        }
      }

      return true;
    }

    Future<void> _onConnect() async {
      if (!_validate()) return;
      setState(() => _isLoading = true);
      try {
        final client = await ref.read(adbClientProvider.future);
        await client.connect(
          _ipCtrl.text.trim(),
          int.parse(_portCtrl.text.trim()),
        );
        if (!mounted) return;
        final serial = '${_ipCtrl.text.trim()}:${_portCtrl.text.trim()}';
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t.devices_page.connected_to(serial: serial))),
        );
        ref.invalidate(adbDevicesWithInfoProvider);
      } on AdbException catch (e) {
        if (!mounted) return;
        if (e.message.contains('already connected')) {
          final serial =
              '${_ipCtrl.text.trim()}:${_portCtrl.text.trim()}';
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(t.devices_page.connected_to(serial: serial))),
          );
          ref.invalidate(adbDevicesWithInfoProvider);
        } else {
          _showSnackbar(e.message);
          setState(() => _step = _DialogStep.pair);
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }

    Future<void> _onPair() async {
      if (!_validate()) return;
      setState(() => _isLoading = true);
      try {
        final client = await ref.read(adbClientProvider.future);
        await client.pair(
          _ipCtrl.text.trim(),
          int.parse(_portCtrl.text.trim()),
          _codeCtrl.text.trim(),
        );
        await client.connect(
          _ipCtrl.text.trim(),
          int.parse(_portCtrl.text.trim()),
        );
        if (!mounted) return;
        final serial = '${_ipCtrl.text.trim()}:${_portCtrl.text.trim()}';
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  t.devices_page.paired_and_connected(serial: serial))),
        );
        ref.invalidate(adbDevicesWithInfoProvider);
      } on AdbException catch (e) {
        if (!mounted) return;
        _showSnackbar(_mapPairError(e.message));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }

    String _mapPairError(String raw) {
      if (raw.toLowerCase().contains('refused')) {
        return t.devices_page.connection_refused;
      }
      if (raw.contains('Invalid pairing code')) {
        return t.devices_page.invalid_pairing_code;
      }
      if (raw.contains('Pairing code must be 6 digits')) {
        return t.devices_page.invalid_code;
      }
      return raw;
    }

    void _showSnackbar(String message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
  ```

- [ ] **Step 5: Wire toolbar button and remove `_showPairDialog`**

  In `DevicesPage.build()`, replace the `add_link` button's `onPressed`:

  ```dart
  // Before:
  onPressed: () => _showPairDialog(context, ref),

  // After:
  onPressed: () => showDialog<void>(
    context: context,
    builder: (_) => const _ConnectPairDialog(),
  ),
  ```

  Then delete the entire `_showPairDialog` method (lines 86–158 in the current file).

  Also add `import 'package:flutter_riverpod/flutter_riverpod.dart';` is already present; verify `ConsumerStatefulWidget` is available — it is, from `flutter_riverpod`.

- [ ] **Step 6: Run all tests — verify they pass**

  ```bash
  cd autoglm_app && flutter test test/devices_page_test.dart --no-pub
  ```

  Expected: All 14 tests pass (6 device-card + 8 dialog).

- [ ] **Step 7: Run full app test suite and analyzer**

  ```bash
  cd /path/to/repo/root && melos run test && melos run analyze
  ```

  Expected: All tests pass, no analysis errors.

- [ ] **Step 8: Commit**

  ```bash
  git add autoglm_app/lib/pages/devices_page.dart \
          autoglm_app/test/devices_page_test.dart
  git commit -m "feat(autoglm_app): add _ConnectPairDialog with progressive connect/pair flow"
  ```

---

## Self-Review Checklist

After completing both tasks, verify against the spec:

- [ ] `_DialogStep` enum has `connect` and `pair` variants
- [ ] Step 1 shows only IP + port; `Key('code_field')` not in tree
- [ ] Step 2 shows IP + port (disabled) + code field with `Key('code_field')`
- [ ] Loading state: `CircularProgressIndicator` replaces buttons; all fields `enabled: false`
- [ ] `already connected` in Step 1 AdbException → treated as success (dialog closes)
- [ ] Step 1 failure → Snackbar with raw message + advance to Step 2
- [ ] Step 2 `[← Back]` resets to Step 1, clears code field
- [ ] Pair success → auto-`connect()` → close dialog → Snackbar `paired_and_connected`
- [ ] `"refused"` substring → `connection_refused` key; `"Invalid pairing code"` → `invalid_pairing_code`; else raw
- [ ] All 15 i18n keys present in both locales
- [ ] 8 dialog tests pass + 6 existing device-card tests still pass
