# 抽离 logger_utils 为独立库设计

- 日期：2026-06-04
- 目标：把 monorepo 内的 `packages/logger_utils` 抽离成独立的公开 GitHub 仓库，长期维护、跨项目以 **git 依赖**复用；monorepo 改为消费该 git 依赖。

## 决策（已确认）

| 项 | 决定 |
|---|---|
| 分发方式 | git 依赖（`git:` url + tag ref），**不**发布 pub.dev |
| 包名 / 仓库名 | 沿用 `logger_utils`（消费方包名引用零改动） |
| git 历史 | 全新开始（不保留旧提交历史） |
| monorepo 内副本 | 移除，5 个消费方改 git 依赖（单一来源=新仓库） |
| 许可证 | MIT |
| GitHub owner | `sunbird89629` → `github.com/sunbird89629/logger_utils` |

## 背景

`logger_utils` 是**纯 Dart 包**（仅依赖 `logging`、`path`，无 Flutter 依赖），含 4 个源文件（`app_logger`/`logger_json`/`logger_trace` + barrel）与 2 个测试。当前被 5 个包依赖：`scrcpy_app`、`scrcpy_flutter`、`scrcpy_mcp`、`scrcpy_plus`、`adb_tools`。

`initLogging()` 全项目约 17 处调用，绝大多数不传 `logsDir`（不写文件），仅 `recording_controller_test.dart` 传 `logsDir`。因此硬编码的 `autoglm-` 文件名前缀目前**几乎不影响实际行为**。

## ① 新仓库结构

```
logger_utils/
├── lib/
│   ├── logger_utils.dart        # barrel（保持现状）
│   ├── app_logger.dart          # initLogging + console/file sink + 按日轮转
│   ├── logger_json.dart         # prettyJson / LoggerJson.infoJson
│   └── logger_trace.dart        # LoggerTrace.trace/traceAsync / dumpValue
├── test/
│   ├── app_logger_test.dart
│   └── logger_trace_test.dart
├── .github/workflows/ci.yaml
├── analysis_options.yaml        # very_good_analysis（沿用）
├── pubspec.yaml
├── README.md
├── CHANGELOG.md
├── LICENSE                      # MIT
└── .gitignore
```

保持现有扁平 `lib/` 结构，不重构进 `lib/src/`（消费方都走 barrel，无收益、徒增风险）。

## ② 通用化改动（向后兼容）

1. `app_logger.dart`：`initLogging` 签名增加可选前缀参数：
   ```dart
   void initLogging({String? logsDir, String filePrefix = 'app'})
   ```
   - 文件名由 `'autoglm-${_dateStamp(today)}.log'` 改为 `'$filePrefix-${_dateStamp(today)}.log'`
   - 轮转清理 `_pruneOldFiles` 内 `startsWith('autoglm-')` 改为 `startsWith('$filePrefix-')`（需把 prefix 传入该函数）
   - 默认 `'app'`；现有裸调用 `initLogging()` 无需修改

2. `pubspec.yaml`：
   - `description` 去掉 "AutoGLM Flutter" 字样，改为通用描述
   - 移除 `resolution: workspace`（独立包，不再是 workspace 成员）
   - 保留 `publish_to: none`（只走 git 依赖，防止误发 pub.dev）
   - 保留 `version: 0.1.0`
   - dependencies：`logging: ^1.3.0`、`path: ^1.9.0`（不变）
   - dev_dependencies：`test: any`、`very_good_analysis: ^7.0.0`（不变；独立纯 Dart 包不受 workspace 的 flutter_test 冲突约束）

## ③ 配套文件

- `LICENSE`：MIT，版权人 `sunbird89629`，年份 2026
- `README.md`：简介 + 安装（git 依赖片段）+ 用法（`initLogging`、`Logger`、`infoJson`、`trace`）+ 级别说明（FINE/INFO/WARNING）
- `CHANGELOG.md`：`## 0.1.0` 首版条目
- `.gitignore`：Dart 标准（`.dart_tool/`、`build/`、`pubspec.lock` 视情况）
- `.github/workflows/ci.yaml`：在 push / PR 上跑 `dart pub get` → `dart format --output=none --set-exit-if-changed .` → `dart analyze --fatal-infos --fatal-warnings` → `dart test`

## ④ monorepo 改造

- 删除 `packages/logger_utils/` 整个目录
- 根 `pubspec.yaml` 的 `workspace:` 列表移除 `packages/logger_utils`
- 5 个消费方 pubspec 的 `logger_utils:` 改为：
  ```yaml
  logger_utils:
    git:
      url: https://github.com/sunbird89629/logger_utils.git
      ref: v0.1.0
  ```
- 本地联调（可选，不纳入本次必做）：根目录 `pubspec_overrides.yaml` 用 `dependency_overrides: { logger_utils: { path: <本地 clone 路径> } }`
- 调用点：无需修改（`initLogging` 新参数向后兼容）

## ⑤ 实施顺序（先有远端仓库，git 依赖才能解析）

1. 本地构建独立库目录：拷贝 4 源文件 + 2 测试，应用通用化改动，新增 LICENSE/README/CHANGELOG/CI/.gitignore；`dart pub get` + `dart test` + `dart analyze` 本地全绿
2. `git init` + 首次提交；`gh repo create sunbird89629/logger_utils --public --source=. --push`；打并推送 tag `v0.1.0`
3. 改造 monorepo：删包、改根 pubspec、改 5 个消费方 pubspec
4. `melos bootstrap` → `melos run analyze` → `melos run test` 全绿

## ⑥ 测试策略

- 独立库：保留现有 `app_logger_test`、`logger_trace_test`；为 `filePrefix` 新增用例（自定义前缀写出 `myprefix-YYYY-MM-DD.log`、默认前缀为 `app-`、轮转仅清理同前缀文件）。CI 三连（format/analyze/test）守门。
- monorepo：rewire 后 `melos bootstrap` 能解析 git 依赖、`melos run analyze` + `melos run test` 全绿，即证明集成正常。

## 非目标（YAGNI）

- 不发布到 pub.dev
- 不重构 `lib/` 为 `lib/src/`
- 不保留旧 git 历史
- 不修改任何 `initLogging()` 调用点
- 本次不强制建立本地 path override（仅作为可选联调说明）
