# Flutter Desktop 骨架 — 设计 Spec

> **背景**：用 Flutter 技术栈重写 AutoGLM-GUI（仅做单机 Flutter Desktop App，砍掉 Docker / headless / cron 场景）。整个重写拆为 7 个子项目；本文档是 **子项目 #1：Monorepo + Flutter Desktop 骨架** 的设计 spec。
>
> **范围决定**（来自 brainstorming 共识）:
> - 部署形态：B2 单机桌面 App（不要 headless、不要服务器部署）
> - 保留功能：A 设备管理、B 实时屏幕预览+手动控制、C GLM Agent 对话、E Workflow、F 历史、G MCP Server
> - 砍掉：cron 定时任务（D）、MAI/Gemini/DroidRun/Midscene Agent（H2-H5）、原项目的 logs / terminal 页面
> - 目标平台：先 macOS（P4），代码尽量跨平台保留，CI/打包暂只做 mac
> - 技术栈：Stack A — Riverpod + go_router + melos + freezed + drift + slang + dio + logger
> - Monorepo 布局：Layout 1 — `apps/` + `packages/` 分层
> - 导航形态：N1 — NavigationRail + 设备侧栏（设备侧栏在 #2 实现）+ 主内容区

---

## 1. Goal & Scope

**Goal**：建立一个可以 `flutter run -d macos` 启动、有 5 个空壳页面、左侧 NavigationRail 可切换的 Flutter Desktop 应用,并搭好 melos monorepo 让后续 6 个子项目能独立开发。

**In Scope**:
- Monorepo 工程结构 + melos 脚本
- Flutter Desktop App 入口、窗口配置、AppShell、路由
- 5 个空壳页面（devices / chat / workflows / history / settings）
- 主题（Material 3 双色 + 系统跟随）
- i18n（zh-CN + en-US，slang）
- 设置存储（JSON 文件，path_provider）
- 日志框架（logger + 文件 rolling）
- Lint / 测试 / 代码生成的工具链
- 验收 DoD

**Out of Scope（留给后续子项目）**：
- 真实 ADB 连接、设备发现、无线配对（→ #2）
- scrcpy 视频流、手动控制（→ #3）
- SQLite / drift schema（→ #4）
- GLM Agent / OpenAI 调用（→ #5）
- 设备侧栏中的真实设备列表（→ #2）
- MCP Server 嵌入（→ #7）
- Windows / Linux 打包
- 自动更新机制
- 原项目 `/logs` `/terminal` `/scheduled-tasks` `/about` 页面

---

## 2. Monorepo 结构

```
autoglm-flutter/
├── apps/
│   └── desktop/                    # Flutter Desktop App
│       ├── lib/
│       │   ├── main.dart           # 入口、ProviderScope、MaterialApp.router
│       │   ├── app.dart            # AppShell + NavigationRail
│       │   ├── router.dart         # go_router 路由表
│       │   ├── i18n/               # slang 源文件 + 生成的 strings.g.dart
│       │   │   ├── zh-CN.i18n.json
│       │   │   └── en-US.i18n.json
│       │   └── pages/              # 5 个空壳页面
│       │       ├── devices_page.dart
│       │       ├── chat_page.dart
│       │       ├── workflows_page.dart
│       │       ├── history_page.dart
│       │       └── settings_page.dart
│       ├── macos/                  # Flutter 自动生成
│       ├── pubspec.yaml
│       └── test/
│           ├── app_shell_test.dart
│           └── router_test.dart
├── packages/
│   ├── autoglm_core/               # 共享 models / errors / settings / logger
│   │   ├── lib/
│   │   │   ├── autoglm_core.dart
│   │   │   └── src/
│   │   │       ├── settings/
│   │   │       │   ├── settings.dart           # freezed Settings 模型
│   │   │       │   ├── settings_repository.dart # 接口
│   │   │       │   └── json_file_settings_repository.dart
│   │   │       └── logging/
│   │   │           └── app_logger.dart
│   │   ├── pubspec.yaml
│   │   └── test/
│   │       ├── json_file_settings_repository_test.dart
│   │       └── app_logger_test.dart
│   └── autoglm_ui_kit/             # 共享主题 + i18n 重导出
│       ├── lib/
│       │   ├── autoglm_ui_kit.dart
│       │   └── src/
│       │       └── theme/
│       │           ├── light_theme.dart
│       │           └── dark_theme.dart
│       ├── pubspec.yaml
│       └── test/
│           └── theme_test.dart
├── melos.yaml                      # workspace + scripts
├── analysis_options.yaml           # 共享 lint
├── .gitignore
└── README.md
```

**说明**：
- 骨架阶段只创建 `autoglm_core` 和 `autoglm_ui_kit` 两个共享包，其他包（`autoglm_adb` / `autoglm_scrcpy` / `autoglm_storage` / `autoglm_agent_glm` / `autoglm_mcp_server`）等对应子项目动工时再加，避免空包污染
- `apps/desktop` 是唯一可运行入口
- 每个包都有 `test/` 目录，骨架阶段就放可跑的 smoke test
- 包名统一前缀 `autoglm_` 避免与社区包冲突

---

## 3. 技术栈版本约束

| 用途 | 包 | 版本约束 | 备注 |
|---|---|---|---|
| Flutter SDK | — | `>=3.24.0` | desktop stable |
| Dart SDK | — | `>=3.5.0 <4.0.0` | |
| 状态管理 | `flutter_riverpod` | `^2.5.1` | |
| | `riverpod_annotation` | `^2.3.5` | |
| | `riverpod_generator` (dev) | `^2.4.0` | |
| 路由 | `go_router` | `^14.2.0` | |
| 数据类 | `freezed` (dev) | `^2.5.2` | |
| | `freezed_annotation` | `^2.4.4` | |
| | `json_annotation` | `^4.9.0` | |
| | `json_serializable` (dev) | `^6.8.0` | |
| HTTP | `dio` | `^5.7.0` | 骨架阶段不直接用，先纳入约束 |
| i18n | `slang` | `^4.4.0` | |
| | `slang_flutter` | `^4.4.0` | |
| 文件路径 | `path_provider` | `^2.1.4` | |
| 日志 | `logger` | `^2.4.0` | |
| Lint | `very_good_analysis` (dev) | `^7.0.0` | |
| Monorepo | `melos` (dev) | `^6.3.0` | |
| Codegen runner | `build_runner` (dev) | `^2.4.13` | |

**版本选取原则**：取写本文档时（2026-04）的稳定版下限，发布到 pub.dev 至少 3 个月，避免 prerelease。

---

## 4. App Shell + 路由

### 4.1 Window 配置（macOS）
- 标题：`AutoGLM`
- 最小尺寸：`1024 × 640`
- 初始尺寸：`1280 × 800`
- 居中显示
- macOS 原生标题栏（不做 frameless）
- macOS entitlements：暂时只勾选 `com.apple.security.network.client`（为后续 LLM HTTP 调用预留）；暂不申请 USB / 文件全盘访问

### 4.2 AppShell
`Scaffold` + `NavigationRail`（左，extended 模式可切换）+ `Expanded(child: child)`（右），其中 `child` 由 `ShellRoute` 注入。

5 个 NavigationRail destination（i18n key + Material icon）：
| 顺序 | 路由 | i18n key | icon | 备注 |
|---|---|---|---|---|
| 1 | `/devices` | `nav.devices` | `Icons.smartphone` | 默认重定向目标 |
| 2 | `/chat` | `nav.chat` | `Icons.chat` | |
| 3 | `/workflows` | `nav.workflows` | `Icons.playlist_play` | |
| 4 | `/history` | `nav.history` | `Icons.history` | |
| 5 | `/settings` | `nav.settings` | `Icons.settings` | |

### 4.3 路由（go_router）
- 使用 `ShellRoute` 包裹 5 个子路由
- 根路径 `/` 重定向到 `/devices`
- 每个空壳页面 build 出一个 `Scaffold(body: Center(child: Text('Devices')))` 之类的占位 UI
- 不在骨架阶段引入 nested route / 动态参数

```dart
final router = GoRouter(
  initialLocation: '/devices',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/devices',   builder: (_, __) => const DevicesPage()),
        GoRoute(path: '/chat',      builder: (_, __) => const ChatPage()),
        GoRoute(path: '/workflows', builder: (_, __) => const WorkflowsPage()),
        GoRoute(path: '/history',   builder: (_, __) => const HistoryPage()),
        GoRoute(path: '/settings',  builder: (_, __) => const SettingsPage()),
      ],
    ),
  ],
);
```

### 4.4 设备侧栏占位
原项目的"第二层侧栏"（设备列表）布局位置预留在 `AppShell` 中：当当前路由 ∈ `{/devices, /chat}` 时，AppShell 在 NavigationRail 和主内容之间渲染一个固定宽度（`240px`）的占位 `Container(child: Text('Device sidebar — #2 implements'))`。其他路由不显示。

骨架不实现真实设备列表，仅为后续子项目 #2 留好布局位。

---

## 5. 主题

- **基底**：Material 3，`useMaterial3: true`
- **配色**：`ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: ...)`，深浅各一套
- **模式切换**：`ThemeMode` 由 Riverpod `themeModeProvider` 管理，三态 `system/light/dark`，持久化到 `Settings.themeMode`
- **字体**：用系统默认（macOS = SF Pro），不引入 Google Fonts
- **共享出口**：`autoglm_ui_kit` 暴露顶层常量 `lightTheme` 和 `darkTheme`，`apps/desktop/main.dart` 直接消费

```dart
// packages/autoglm_ui_kit/lib/src/theme/light_theme.dart
final lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: Brightness.light,
  ),
);
```

---

## 6. i18n

### 6.1 方案
- `slang` + `slang_flutter`（type-safe，运行时无字符串 key）
- 默认语言：跟随系统（`Platform.localeName`），不在支持列表里时回落 `zh-CN`
- 在 `/settings` 提供手动覆盖（`system / zh-CN / en-US`）

### 6.2 目录与文件
- 源文件：`apps/desktop/lib/i18n/zh-CN.i18n.json`、`en-US.i18n.json`
- 生成产物：`apps/desktop/lib/i18n/strings.g.dart`（git 提交）
- codegen 命令：`dart run slang`，由 `melos run gen:i18n` 触发

### 6.3 骨架阶段字符串集
共 16 条 key（每条对应 zh-CN 和 en-US 两份值）:

| key | zh-CN | en-US |
|---|---|---|
| `app.title` | AutoGLM | AutoGLM |
| `nav.devices` | 设备 | Devices |
| `nav.chat` | 对话 | Chat |
| `nav.workflows` | 工作流 | Workflows |
| `nav.history` | 历史 | History |
| `nav.settings` | 设置 | Settings |
| `page.devices.placeholder` | 设备列表（子项目 #2 实现） | Devices (implemented in #2) |
| `page.chat.placeholder` | 对话与屏幕（子项目 #3、#5 实现） | Chat & Screen (implemented in #3, #5) |
| `page.workflows.placeholder` | 工作流（待实现） | Workflows (TBD) |
| `page.history.placeholder` | 历史（子项目 #4 实现） | History (implemented in #4) |
| `settings.theme.label` | 主题 | Theme |
| `settings.theme.system` | 跟随系统 | System |
| `settings.theme.light` | 浅色 | Light |
| `settings.theme.dark` | 深色 | Dark |
| `settings.locale.label` | 语言 | Language |
| `settings.locale.system` | 跟随系统 | System |

---

## 7. 设置存储

### 7.1 存储位置
- `path_provider` 的 `getApplicationSupportDirectory()` 下的 `settings.json`
- macOS 实际路径：`~/Library/Application Support/AutoGLM/settings.json`

### 7.2 抽象层
`autoglm_core` 暴露：
- `abstract class SettingsRepository` —— 接口（`Future<Settings> load()`、`Future<void> save(Settings)`）
- `class JsonFileSettingsRepository implements SettingsRepository` —— 实现，构造接收一个 `File` 参数（便于测试用临时目录）
- Riverpod provider `settingsRepositoryProvider`，apps 层覆盖以注入实际 file 路径

### 7.3 Settings 模型
```dart
@freezed
class Settings with _$Settings {
  const factory Settings({
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default('system') String locale,                 // 'system' | 'zh-CN' | 'en-US'
    @Default('https://open.bigmodel.cn/api/paas/v4') String llmBaseUrl,
    @Default('autoglm-phone') String llmModel,
    @Default('') String llmApiKey,
    @Default(false) bool mcpServerEnabled,
    @Default(8765) int mcpServerPort,
  }) = _Settings;

  factory Settings.fromJson(Map<String, dynamic> json) => _$SettingsFromJson(json);
}
```

### 7.4 写入策略
- 修改 `Settings` 即触发 Riverpod `settingsProvider.notifier` 的 `update`
- Notifier 内部 `debounce 500ms` 后整文件覆写（小文件不需要增量更新）
- 文件不存在时，加载返回默认值并主动写一次

### 7.5 不用 `shared_preferences`
- 跨平台一致性差（macOS 走 NSUserDefaults，文件位置随 bundle id 变）
- 用户排查问题不便（看不到 plist 里塞了什么）
- JSON 文件在所有平台行为一致，便于备份和肉眼检查

---

## 8. 日志

- 包：`logger`（pub.dev `logger`）
- 级别：`Level.debug / info / warning / error`
- 输出：控制台 + 文件
- 文件位置：`<logsDir>/autoglm-YYYY-MM-DD.log`，生产 `<logsDir>` = `getApplicationSupportDirectory()/logs`
- Rolling 策略：单文件 ≤ 5 MB，保留最近 5 个文件，超出按文件名时间戳删除最旧
- API 设计：
  - `autoglm_core` 暴露 `class AppLogger` —— 构造接收 `Directory logsDir`（便于测试用临时目录）
  - 同时暴露顶层 `late final AppLogger appLogger`，由 apps 层在 `main()` 启动时调用 `initAppLogger(productionLogsDir)` 初始化一次
  - 包代码统一 `import 'package:autoglm_core/autoglm_core.dart' show appLogger;` 后用 `appLogger.i(...)`
- 骨架阶段：实现日志框架本身 + 启动时打印 `appLogger.i('AutoGLM started, version=...')`，UI 中不暴露日志查看入口

---

## 9. 测试策略（骨架阶段）

| 包 | 测试 | 类型 |
|---|---|---|
| `autoglm_core` | `JsonFileSettingsRepository` 读写 round-trip（临时目录） | unit |
| `autoglm_core` | `JsonFileSettingsRepository.load()` 在文件不存在时返回默认值 | unit |
| `autoglm_core` | `AppLogger(tempDir)` 能在指定目录创建日志文件并写入一行 | unit |
| `autoglm_ui_kit` | `lightTheme` / `darkTheme` 构造不抛异常的 smoke test | unit |
| `apps/desktop` | `AppShell` widget 渲染时含 5 个 NavigationRail destination | widget |
| `apps/desktop` | 点击第 N 个 destination 后 router 当前路径切换到对应路由 | widget |
| `apps/desktop` | 在 `/devices` 和 `/chat` 路由下显示 Device sidebar 占位；在其他路由下不显示 | widget |
| `apps/desktop` | 切换 `Settings.locale` 后 NavigationRail 标签文案立即切换 | widget |
| `apps/desktop` | App 启动 smoke test（`testWidgets('app boots', ...)`），构造 `MaterialApp.router` 不报错 | widget |

**目标**：`melos run test` 全绿。覆盖率不强求（骨架阶段）。

---

## 10. 工具链

### 10.1 melos.yaml 脚本
```yaml
name: autoglm_flutter
packages:
  - apps/*
  - packages/*

scripts:
  bootstrap:
    description: Install all package deps
    run: melos bootstrap

  analyze:
    description: Run dart analyze on all packages
    exec: dart analyze --fatal-infos --fatal-warnings

  format:
    description: Check formatting
    exec: dart format --set-exit-if-changed .

  test:
    description: Run all tests
    exec: flutter test

  gen:
    description: Run build_runner for all packages that need it
    exec: dart run build_runner build --delete-conflicting-outputs
    packageFilters:
      dependsOn: build_runner

  gen:i18n:
    description: Regenerate slang strings
    run: cd apps/desktop && dart run slang
```

### 10.2 Lint
根目录 `analysis_options.yaml`：
```yaml
include: package:very_good_analysis/analysis_options.yaml
analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
```

### 10.3 Git hooks
不强制装；提供 `lefthook.yml` 供愿意装的人挂上：
```yaml
pre-commit:
  commands:
    format:
      run: dart format --set-exit-if-changed {staged_files}
    analyze:
      run: melos run analyze
```

### 10.4 CI
骨架阶段**不配** GitHub Actions，避免在 mac-only 阶段花时间在 runner 矩阵上。仓库根放一个 `.github/workflows/ci.yml.todo` 占位文件作为备忘（说明：等到 #2 完成再启用）。

---

## 11. Definition of Done

骨架完成的判定（一个新人 5 分钟内可验证）:
1. `git clone <repo>` 后执行 `dart pub global activate melos && melos bootstrap` 无错误
2. `melos run gen:i18n` + `melos run gen` 成功生成代码
3. `melos run analyze` 输出 `0 issues`
4. `melos run format` 无 diff
5. `melos run test` 全绿
6. `cd apps/desktop && flutter run -d macos` 启动后看到：
   - 1280×800 窗口，标题 "AutoGLM"
   - 左侧 NavigationRail 含 5 个 destination
   - 默认进入 `/devices` 空页（占位文字 "设备列表（子项目 #2 实现）"）
   - 点击其他 destination 可切换页面
   - 在 `/devices` 和 `/chat` 路由下，NavigationRail 与主内容之间出现 240px 宽的"Device sidebar"占位区；其他路由不出现
   - 系统切换深浅色时 App 跟随
7. 设置页改主题模式后，重启 App 仍然记得选择
8. 设置页改语言后，UI 文案立即切换（无需重启）
9. `~/Library/Application Support/AutoGLM/` 下能看到 `settings.json` 和 `logs/` 目录，日志文件含 "AutoGLM started" 行

---

## 12. 风险与未决问题

| 风险 | 缓解 |
|---|---|
| `slang` 在 Flutter 3.24+ 的兼容性 | 第一次 spike 时验证；如失败回落到 `intl` + `.arb` |
| `very_good_analysis` 7.0 对部分规则过严 | `analysis_options.yaml` 中针对性 disable，不放任意 ignore |
| `path_provider` 在 macOS sandbox 下路径不同 | 骨架阶段未启用 sandbox（普通 dev build），打包阶段单独处理 |
| 后续子项目可能需要不同的 settings 字段 | `Settings` 用 freezed + `@JsonKey` 注解，加字段都是非破坏性，旧 JSON 自动用默认值兜底 |
