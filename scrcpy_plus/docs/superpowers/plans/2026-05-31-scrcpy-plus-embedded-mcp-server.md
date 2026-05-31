# scrcpy_plus 内嵌 MCP server + 托盘显示连接地址 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 scrcpy_plus 开机自动启动一个内嵌 MCP server，并在托盘菜单顶部显示可点击复制的连接地址 `http://localhost:7070/mcp`。

**Architecture:** scrcpy_plus 新增 path 依赖 `scrcpy_mcp`，复用其 `McpHttpServer`（单 server 管所有设备，HTTP/Streamable transport）。新增 `McpServerController` 包装其生命周期；`ScrcpyConfig` 增加 `mcpPort`；`MenuBuilder` 增加 MCP 状态段；`AppController` 在 init 时自动启动、退出时停止，并处理"复制地址"菜单点击。

**Tech Stack:** Dart / Flutter (macOS), `tray_manager`, `scrcpy_mcp` (→ `scrcpy_client`, `mcp_dart`), `adb_tools`, `flutter/services` Clipboard, `osascript`。

---

## File Structure

- Create: `lib/mcp/mcp_server_controller.dart` — 包装 `McpHttpServer` 的生命周期与状态。
- Create: `test/mcp/mcp_server_controller_test.dart` — controller 的 start/stop/url/error 测试。
- Modify: `pubspec.yaml` — 新增 `scrcpy_mcp` path 依赖。
- Modify: `lib/scrcpy/scrcpy_config.dart` — 新增 `mcpPort` 字段。
- Modify: `test/scrcpy/scrcpy_config_test.dart` — `mcpPort` 默认值与 round-trip。
- Modify: `lib/app/menu_builder.dart` — 顶部 MCP 状态段 + `copyMcpKey` 常量。
- Modify: `test/app/menu_builder_test.dart` — 三种 MCP 状态的菜单结构。
- Modify: `lib/app/app_controller.dart` — 持有并自动启停 controller，处理 `mcp_copy`。

---

## Task 1: ScrcpyConfig 增加 mcpPort 字段

**Files:**
- Modify: `lib/scrcpy/scrcpy_config.dart`
- Test: `test/scrcpy/scrcpy_config_test.dart`

- [ ] **Step 1: Write the failing tests**

在 `test/scrcpy/scrcpy_config_test.dart` 的 `group('ScrcpyConfig', ...)` 内追加：

```dart
    test('mcpPort defaults to 7070', () {
      const config = ScrcpyConfig();
      expect(config.mcpPort, 7070);
    });

    test('mcpPort survives toJson/fromJson round-trip', () {
      const config = ScrcpyConfig(mcpPort: 8123);
      final restored = ScrcpyConfig.fromJson(config.toJson());
      expect(restored.mcpPort, 8123);
    });

    test('fromJson falls back to 7070 when mcpPort absent', () {
      final restored = ScrcpyConfig.fromJson({'scrcpyPath': 'scrcpy'});
      expect(restored.mcpPort, 7070);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scrcpy_plus && flutter test test/scrcpy/scrcpy_config_test.dart`
Expected: FAIL — `mcpPort` 不是 ScrcpyConfig 的成员。

- [ ] **Step 3: Add the mcpPort field**

编辑 `lib/scrcpy/scrcpy_config.dart`，把构造、字段、toJson、fromJson 改为：

```dart
/// Configuration for scrcpy CLI parameters.
class ScrcpyConfig {
  const ScrcpyConfig({
    this.scrcpyPath = 'scrcpy',
    this.maxSize = 1024,
    this.videoBitRate = '8M',
    this.videoCodec = 'h264',
    this.mcpPort = 7070,
  });

  final String scrcpyPath;
  final int maxSize;
  final String videoBitRate;
  final String videoCodec;
  final int mcpPort;

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
        'mcpPort': mcpPort,
      };

  factory ScrcpyConfig.fromJson(Map<String, dynamic> json) {
    return ScrcpyConfig(
      scrcpyPath: json['scrcpyPath'] as String? ?? 'scrcpy',
      maxSize: json['maxSize'] as int? ?? 1024,
      videoBitRate: json['videoBitRate'] as String? ?? '8M',
      videoCodec: json['videoCodec'] as String? ?? 'h264',
      mcpPort: json['mcpPort'] as int? ?? 7070,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scrcpy_plus && flutter test test/scrcpy/scrcpy_config_test.dart`
Expected: PASS（全部用例通过）。

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/scrcpy/scrcpy_config.dart scrcpy_plus/test/scrcpy/scrcpy_config_test.dart
git commit -m "feat(scrcpy_plus): add mcpPort to ScrcpyConfig"
```

---

## Task 2: 新增 scrcpy_mcp 依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

编辑 `scrcpy_plus/pubspec.yaml`，在 `dependencies:` 下（`tray_manager` 之前）加入：

```yaml
  scrcpy_mcp:
    path: ../scrcpy_mcp
```

加完后 `dependencies:` 应为：

```yaml
dependencies:
  adb_tools:
    path: ../packages/adb_tools
  logger_utils:
    path: ../packages/logger_utils
  scrcpy_mcp:
    path: ../scrcpy_mcp
  flutter:
    sdk: flutter
  tray_manager: ^0.4.0
  path: ^1.9.0
```

- [ ] **Step 2: Bootstrap the workspace**

Run: `cd /Users/hao/ai/mobile/asf_dev && melos bootstrap`
Expected: 成功解析依赖，scrcpy_mcp / scrcpy_client / mcp_dart 链接进来，无版本冲突错误。

- [ ] **Step 3: Verify it resolves and analyzes**

Run: `cd scrcpy_plus && dart analyze`
Expected: No issues found（依赖加入后仍能通过分析）。

- [ ] **Step 4: Commit**

```bash
git add scrcpy_plus/pubspec.yaml pubspec.lock
git commit -m "build(scrcpy_plus): depend on scrcpy_mcp"
```

> 注：若 `pubspec.lock` 不在 scrcpy_plus 下（workspace 模式锁文件在根），改为 `git add scrcpy_plus/pubspec.yaml` 加根 `pubspec.lock`（若有变更）。

---

## Task 3: McpServerController

**Files:**
- Create: `lib/mcp/mcp_server_controller.dart`
- Test: `test/mcp/mcp_server_controller_test.dart`

依赖参考：`scrcpy_mcp` 暴露 `McpHttpServer`、`ScrcpyMcpAdb`；`scrcpy_client` 暴露 `ScrcpySessionImpl.create({required ScrcpyAdb adb})`；`adb_tools` 暴露 `AdbClient`。`McpHttpServer.start({required int port, required ScrcpySession session, required ScrcpyAdb adb, RecordingAdb? recordingAdb})`，`serverUrl` getter 返回 `http://localhost:<port>/mcp` 或 null，`stop()` 释放。

- [ ] **Step 1: Write the failing test**

创建 `test/mcp/mcp_server_controller_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_plus/mcp/mcp_server_controller.dart';

void main() {
  group('McpServerController', () {
    test('serverUrl is null and not running before start', () {
      final controller = McpServerController(adb: const AdbClient());
      expect(controller.isRunning, false);
      expect(controller.serverUrl, isNull);
      expect(controller.errorMessage, isNull);
    });

    test('start exposes a localhost mcp url, stop tears it down', () async {
      final controller = McpServerController(adb: const AdbClient());
      await controller.start(7099);
      expect(controller.errorMessage, isNull);
      expect(controller.isRunning, true);
      expect(controller.serverUrl, 'http://localhost:7099/mcp');
      await controller.stop();
      expect(controller.isRunning, false);
      expect(controller.serverUrl, isNull);
    });

    test('start on an in-use port records errorMessage without throwing',
        () async {
      final first = McpServerController(adb: const AdbClient());
      await first.start(7098);
      final second = McpServerController(adb: const AdbClient());
      await second.start(7098); // same port — should fail gracefully
      expect(second.isRunning, false);
      expect(second.errorMessage, isNotNull);
      await first.stop();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scrcpy_plus && flutter test test/mcp/mcp_server_controller_test.dart`
Expected: FAIL — `mcp_server_controller.dart` 不存在 / 类型未定义。

- [ ] **Step 3: Implement the controller**

创建 `lib/mcp/mcp_server_controller.dart`：

```dart
import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

/// Owns the embedded MCP HTTP server lifecycle for scrcpy_plus.
///
/// Wraps scrcpy_mcp's [McpHttpServer]: builds a [ScrcpyMcpAdb] from the app's
/// [AdbClient], creates a [ScrcpySession], and starts/stops a single shared
/// Streamable HTTP MCP endpoint. Startup failures are captured into
/// [errorMessage] rather than thrown, so the tray app keeps running.
class McpServerController {
  McpServerController({required AdbClient adb}) : _adb = ScrcpyMcpAdb(adb);

  final ScrcpyMcpAdb _adb;
  final McpHttpServer _server = McpHttpServer();

  bool _running = false;
  String? _errorMessage;

  bool get isRunning => _running;
  String? get serverUrl => _server.serverUrl;
  String? get errorMessage => _errorMessage;

  /// Start the MCP server on [port]. Captures failures into [errorMessage].
  Future<void> start(int port) async {
    _errorMessage = null;
    try {
      final session = await ScrcpySessionImpl.create(adb: _adb);
      await _server.start(
        port: port,
        session: session,
        adb: _adb,
        recordingAdb: _adb,
      );
      _running = true;
    } catch (e) {
      _errorMessage = e.toString();
      _running = false;
    }
  }

  Future<void> stop() async {
    await _server.stop();
    _running = false;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scrcpy_plus && flutter test test/mcp/mcp_server_controller_test.dart`
Expected: PASS。若 `ScrcpySessionImpl.create` 因找不到 scrcpy-server JAR 资源而报错，确认 `melos bootstrap` 已执行且 `packages/scrcpy_client/assets/` 存在该 JAR；该路径由包内 `Isolate.resolvePackageUri` 解析，测试环境下可用。

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/mcp/mcp_server_controller.dart scrcpy_plus/test/mcp/mcp_server_controller_test.dart
git commit -m "feat(scrcpy_plus): add McpServerController wrapping McpHttpServer"
```

---

## Task 4: MenuBuilder 显示 MCP 状态段

**Files:**
- Modify: `lib/app/menu_builder.dart`
- Test: `test/app/menu_builder_test.dart`

- [ ] **Step 1: Write the failing tests**

在 `test/app/menu_builder_test.dart` 的 `group('MenuBuilder', ...)` 内追加：

```dart
    test('buildMenu shows mcp url and copy item when running', () {
      final menu = MenuBuilder.buildMenu(
        devices: [],
        mcpUrl: 'http://localhost:7070/mcp',
      );
      final copyItem = menu.items!.firstWhere(
        (i) => i.key == MenuBuilder.copyMcpKey,
      );
      expect(copyItem.label, contains('http://localhost:7070/mcp'));
    });

    test('buildMenu shows mcp error line when error present', () {
      final menu = MenuBuilder.buildMenu(
        devices: [],
        mcpError: 'port in use',
      );
      final labels = menu.items!.map((i) => i.label).toList();
      expect(labels.any((l) => l != null && l.contains('port in use')), true);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, isNot(contains(MenuBuilder.copyMcpKey)));
    });

    test('buildMenu omits mcp section when no url and no error', () {
      final menu = MenuBuilder.buildMenu(devices: []);
      final keys = menu.items!.map((i) => i.key).toList();
      expect(keys, isNot(contains(MenuBuilder.copyMcpKey)));
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scrcpy_plus && flutter test test/app/menu_builder_test.dart`
Expected: FAIL — `copyMcpKey` 未定义 / `buildMenu` 不接受 `mcpUrl`、`mcpError` 参数。

- [ ] **Step 3: Add the MCP section to MenuBuilder**

编辑 `lib/app/menu_builder.dart`：新增 `copyMcpKey` 常量；给 `buildMenu` 增加可选参数；在 `items` 构建最前面插入 MCP 段。完整替换为：

```dart
import 'package:tray_manager/tray_manager.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

/// Builds the tray context menu from current app state.
class MenuBuilder {
  /// Key prefixes used for menu item identification.
  static const String launchPrefix = 'launch_';
  static const String disconnectPrefix = 'disconnect_';
  static const String infoPrefix = 'info_';

  /// Key for the "copy MCP address" menu item.
  static const String copyMcpKey = 'mcp_copy';

  static Menu buildMenu({
    required List<DeviceEntry> devices,
    String? mcpUrl,
    String? mcpError,
  }) {
    final items = <MenuItem>[];

    // MCP server status section (top).
    if (mcpUrl != null) {
      items.add(MenuItem(key: 'mcp_header', label: 'MCP server', disabled: true));
      items.add(MenuItem(key: copyMcpKey, label: '  $mcpUrl'));
      items.add(MenuItem.separator());
    } else if (mcpError != null) {
      items.add(MenuItem(
        key: 'mcp_error',
        label: 'MCP server: $mcpError',
        disabled: true,
      ));
      items.add(MenuItem.separator());
    }

    if (devices.isEmpty) {
      items.add(MenuItem(
        key: 'no_devices',
        label: 'No devices connected',
        disabled: true,
      ));
    } else {
      for (final device in devices) {
        items.add(MenuItem(
          key: '$launchPrefix${device.serial}',
          label: 'Launch scrcpy: ${device.menuLabel}',
        ));
        items.add(MenuItem(
          key: '$disconnectPrefix${device.serial}',
          label: '  Disconnect ${device.displayName}',
        ));
        if (device.detailLine != null) {
          items.add(MenuItem(
            key: '$infoPrefix${device.serial}',
            label: '  ${device.detailLine}',
            disabled: true,
          ));
        }
      }
    }

    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'pair', label: 'Pair new device...'));
    items.add(MenuItem(key: 'refresh', label: 'Refresh devices'));
    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'settings', label: 'Settings...'));
    items.add(MenuItem(key: 'quit', label: 'Quit'));

    return Menu(items: items);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scrcpy_plus && flutter test test/app/menu_builder_test.dart`
Expected: PASS（新旧用例全过）。

- [ ] **Step 5: Commit**

```bash
git add scrcpy_plus/lib/app/menu_builder.dart scrcpy_plus/test/app/menu_builder_test.dart
git commit -m "feat(scrcpy_plus): show MCP server address in tray menu"
```

---

## Task 5: AppController 接线（自动启停 + 复制处理）

**Files:**
- Modify: `lib/app/app_controller.dart`

此任务接 tray_manager 实例与系统副作用（剪贴板、osascript、通知），按现有 `app_controller_test.dart` 约定无法单测（需真实 tray_manager），通过 `dart analyze` + 手动运行验证。

- [ ] **Step 1: Add imports**

在 `lib/app/app_controller.dart` 顶部 imports 区加入：

```dart
import 'package:flutter/services.dart';
import 'package:scrcpy_plus/mcp/mcp_server_controller.dart';
```

- [ ] **Step 2: Hold the controller and start it in init**

在字段区（`late final ScrcpyLauncher launcher;` 之后）加入：

```dart
  late final McpServerController mcpController;
```

在构造体（`launcher = ScrcpyLauncher();` 之后）加入：

```dart
    mcpController = McpServerController(adb: this.adb);
```

把 `init()` 改为在托盘初始化后启动 MCP server：

```dart
  Future<void> init() async {
    final config = await settingsManager.loadConfig();
    launcher.config = config;

    deviceManager.addListener(_updateTrayMenu);
    await deviceManager.refresh();
    deviceManager.startPolling();

    await _initTray();

    await mcpController.start(config.mcpPort);
    await _updateTrayMenu();
  }
```

- [ ] **Step 3: Pass MCP state into the menu**

把 `_updateTrayMenu()` 改为传入 MCP 状态：

```dart
  Future<void> _updateTrayMenu() async {
    final menu = MenuBuilder.buildMenu(
      devices: deviceManager.devices,
      mcpUrl: mcpController.serverUrl,
      mcpError: mcpController.errorMessage,
    );
    await trayManager.setContextMenu(menu);

    // Update icon based on connection state
    final icon = deviceManager.hasConnected
        ? 'assets/tray_icon_connected.png'
        : 'assets/tray_icon.png';
    await trayManager.setIcon(icon);
  }
```

- [ ] **Step 4: Handle the copy action**

在 `onTrayMenuItemClick` 的 if/else 链里，`key == 'settings'` 分支之后加入：

```dart
    } else if (key == MenuBuilder.copyMcpKey) {
      _copyMcpUrl();
```

并新增方法（放在 `_showSettingsDialog` 附近）：

```dart
  Future<void> _copyMcpUrl() async {
    final url = mcpController.serverUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    try {
      await Process.run('osascript', [
        '-e',
        'display notification "MCP address copied" with title "scrcpy_plus"',
      ]);
    } catch (e) {
      appLogger.warning('Failed to show copy notification: $e');
    }
  }
```

> `MenuBuilder` 已在文件中 import；`Process` 来自已有的 `dart:io` import。

- [ ] **Step 5: Stop the server on quit and dispose**

把 `_quit()` 与 `dispose()` 改为停止 MCP server：

```dart
  void _quit() {
    launcher.dispose();
    deviceManager.dispose();
    mcpController.stop();
    trayManager.destroy();
    exit(0);
  }

  void dispose() {
    launcher.dispose();
    deviceManager.dispose();
    mcpController.stop();
    trayManager.removeListener(this);
  }
```

- [ ] **Step 6: Analyze and run existing tests**

Run: `cd scrcpy_plus && dart analyze && flutter test`
Expected: analyze 无问题；全部测试通过（含先前任务新增用例）。

- [ ] **Step 7: Commit**

```bash
git add scrcpy_plus/lib/app/app_controller.dart
git commit -m "feat(scrcpy_plus): auto-start embedded MCP server and wire copy action"
```

---

## Task 6: 手动验证 + 收尾

**Files:** 无（手动验证）

- [ ] **Step 1: Run the app**

Run: `cd scrcpy_plus && flutter run -d macos`
Expected: 应用以托盘形式启动，无崩溃。

- [ ] **Step 2: Verify the tray menu**

点击托盘图标，确认顶部出现：
- `MCP server`（灰色标题）
- `  http://localhost:7070/mcp`（可点击）

点击该 URL 项 → 出现 "MCP address copied" 系统通知，剪贴板内容为该 URL（可在任意输入框粘贴验证）。

- [ ] **Step 3: Verify MCP connectivity (optional)**

在支持 streamable-http 的 MCP 客户端配置 `{"type":"http","url":"http://localhost:7070/mcp"}`，确认能列出 `list_devices` 等工具。

- [ ] **Step 4: Full workspace checks**

Run: `cd /Users/hao/ai/mobile/asf_dev && melos run analyze && melos run test`
Expected: analyze 与 test 全绿。

---

## Self-Review notes

- Spec 覆盖：单一共享端点(Task 2/3)、自动启动(Task 5)、托盘显示+复制(Task 4/5)、mcpPort 持久化(Task 1)、错误处理(Task 3 errorMessage + Task 4 菜单展示)、停止释放(Task 5)、测试(Task 1/3/4) 均有对应任务。范围外项（Settings UI、每设备端点）未纳入，符合 spec。
- 类型一致性：`McpServerController({required AdbClient adb})`、`start(int port)`、`stop()`、`serverUrl`、`errorMessage`、`isRunning`、`MenuBuilder.copyMcpKey`、`buildMenu({devices, mcpUrl, mcpError})` 在各任务间命名一致。
