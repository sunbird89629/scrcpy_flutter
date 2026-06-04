# scrcpy_plus 内嵌 MCP server + 托盘显示连接地址 — 设计文档

日期：2026-05-31
状态：已批准，待实现

## 背景与问题

`scrcpy_plus` 目前是一个纯托盘（macOS menu bar）应用，作用是 shell 调起原生
`scrcpy` 二进制来投屏，自身**没有任何 MCP 能力**。MCP server 实现位于隔壁
`scrcpy_mcp` 包（`ScrcpyMcpServer` + `McpHttpServer`），由 `scrcpy_app` 托管。

需求：让用户点击托盘图标时能看到一个 MCP 连接地址，从而把 Claude / Cursor 等
MCP 客户端接到 `scrcpy_plus`，控制已连接的 Android 设备。

## 关键设计决策

- **单一共享端点**：复用 `scrcpy_mcp` 现有的"单 server 管所有设备"模型。一个
  `StreamableMcpServer`，URL = `http://localhost:<port>/mcp`。设备通过工具参数
  （如 `start_mirroring(device_id)`）选择，而非每设备一个端点。
- **直接依赖 `scrcpy_mcp`**：`scrcpy_plus` 新增 path 依赖 `scrcpy_mcp`，复用现成
  的 `McpHttpServer`，不重写 MCP 协议逻辑。会传递引入 `scrcpy_client`、`mcp_dart`。
- **开机自动启动**：app 启动时自动起 MCP server，托盘菜单顶部展示并支持点击复制。

### 已知特性（非阻塞）

MCP server 走的是 `scrcpy_client` 的进程内 session，与托盘 "Launch scrcpy" 调起
的原生 scrcpy 窗口是两条**独立**的镜像通道。两者可并存，互不干扰。

## 架构与组件

```
AppController.init()
  ├─ 加载 ScrcpyConfig（含 mcpPort，默认 7070）
  ├─ 起托盘
  └─ McpServerController.start(config.mcpPort)
         └─ McpHttpServer（来自 scrcpy_mcp）
                └─ StreamableMcpServer → ScrcpyMcpServer
```

### 1. `lib/mcp/mcp_server_controller.dart`（新增）

包一层 `scrcpy_mcp` 的 `McpHttpServer`：

- 构造：用现有 `AdbClient` → `ScrcpyMcpAdb`，`ScrcpySessionImpl.create(adb: ...)`
  建 session。
- `Future<void> start(int port)` / `Future<void> stop()`。
- 暴露 `bool isRunning`、`String? serverUrl`、`String? errorMessage`。
- 启动失败（端口占用等）捕获异常存入 `errorMessage`，不抛出、不崩溃。

### 2. `ScrcpyConfig`（`lib/scrcpy/scrcpy_config.dart`，修改）

新增字段 `int mcpPort`，默认 `7070`，纳入 `toJson` / `fromJson`（fromJson 缺省回退
7070）。

### 3. `AppController`（`lib/app/app_controller.dart`，修改）

- 持有 `late final McpServerController mcpController`。
- `init()` 中建好托盘后调用 `mcpController.start(config.mcpPort)`。
- `_updateTrayMenu()` 把 `mcpController.serverUrl` / `errorMessage` 传给
  `MenuBuilder.buildMenu`。
- `onTrayMenuItemClick` 处理 key `mcp_copy`：写剪贴板 + 弹系统通知。
- `_quit()` / `dispose()` 调用 `mcpController.stop()`。

### 4. `MenuBuilder.buildMenu`（`lib/app/menu_builder.dart`，修改）

新增参数 `String? mcpUrl`、`String? mcpError`。在菜单**顶部**插入一段：

- 运行中（`mcpUrl != null`）：
  - `MenuItem(label: 'MCP server', disabled: true)`
  - `MenuItem(key: 'mcp_copy', label: '  $mcpUrl')`（点击复制）
  - `MenuItem.separator()`
- 出错（`mcpError != null`）：
  - `MenuItem(label: 'MCP server: $mcpError', disabled: true)`
  - `MenuItem.separator()`
- 新增 key 常量 `copyMcpKey = 'mcp_copy'`。

### 5. 复制反馈

`onTrayMenuItemClick` 处理 `mcp_copy`：

- 用 `Clipboard.setData(ClipboardData(text: url))`（Flutter 引擎已运行，平台通道可用）
  写入剪贴板。
- 用 `osascript -e 'display notification "MCP address copied" with title "scrcpy_plus"'`
  弹系统通知（与现有 PairDialog / SettingsDialog 的 osascript 用法一致）。

## 数据流

启动 → 加载 config（含 mcpPort）→ `McpServerController.start` → `_updateTrayMenu`
读取 `serverUrl`/`errorMessage` 传入 `MenuBuilder` → 用户点 `mcp_copy` → 写剪贴板
+ 通知。

## 错误处理

- 端口被占用 / 启动失败：`McpServerController` 捕获，`errorMessage` 非空，菜单显示
  错误行，app 正常运行。
- 退出：`_quit()` / `dispose()` 调 `mcpController.stop()` 释放端口。

## 测试

- `test/mcp_server_controller_test.dart`：start/stop 生命周期、`serverUrl` 格式
  （`http://localhost:<port>/mcp`）、错误捕获（占用端口或注入失败）。
- `test/menu_builder_test.dart`（扩展）：三种状态的菜单结构——有 url / 有 error /
  无 MCP 信息。
- `test/scrcpy_config_test.dart`（扩展或新增）：`mcpPort` 的 toJson/fromJson 与
  默认值 7070。

## 范围外（YAGNI）

- Settings UI 改端口：当前 settings dialog 仍是 TODO 桩，本期只把 `mcpPort`
  持久化到 config 文件，不做 UI。
- 每设备独立端点 / 手动开关：本期不做。
