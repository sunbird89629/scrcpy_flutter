# logger_utils 独立库抽离 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 monorepo 内的 `packages/logger_utils` 抽离成独立公开 GitHub 仓库 `sunbird89629/logger_utils`（MIT），monorepo 改为以 git 依赖（锁定 tag `v0.1.0`）消费。

**Architecture:** 先在 `/Users/hao/ai/mobile/logger_utils` 本地构建独立纯 Dart 包（拷贝源文件、把硬编码 `autoglm-` 日志前缀参数化为 `filePrefix`、补 LICENSE/README/CHANGELOG/CI），推送并打 tag；再回到 monorepo（`asf_dev` worktree，`dev` 分支）删除本地包、把 5 个消费方 pubspec 的 path 依赖改为 git 依赖。

**Tech Stack:** Dart (SDK ^3.10, 本机 3.11.5)，`logging`/`path`，`test`，`very_good_analysis`，melos 工作区，`gh` CLI，GitHub Actions。

**约定：**
- 独立库路径：`/Users/hao/ai/mobile/logger_utils`（下称 `$LIB`）
- monorepo 根：`/Users/hao/ai/mobile/asf_dev`（下称 `$MONO`，当前在 `dev` 分支）
- 源文件来源：`$MONO/packages/logger_utils/`
- Task 1–4 在 `$LIB` 操作；Task 5 在 `$MONO` 操作。

---

### Task 1: 在 $LIB 搭建独立库骨架并原样拷贝源码/测试（本地全绿）

**Files:**
- Create dir: `/Users/hao/ai/mobile/logger_utils/`
- Copy: `lib/logger_utils.dart`, `lib/app_logger.dart`, `lib/logger_json.dart`, `lib/logger_trace.dart`, `test/app_logger_test.dart`, `test/logger_trace_test.dart`（从 `$MONO/packages/logger_utils/` 原样拷贝）
- Create: `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`

- [ ] **Step 1: 建目录并拷贝源文件与测试（保持内容不变）**

```bash
LIB=/Users/hao/ai/mobile/logger_utils
SRC=/Users/hao/ai/mobile/asf_dev/packages/logger_utils
mkdir -p "$LIB/lib" "$LIB/test"
cp "$SRC/lib/logger_utils.dart" "$SRC/lib/app_logger.dart" "$SRC/lib/logger_json.dart" "$SRC/lib/logger_trace.dart" "$LIB/lib/"
cp "$SRC/test/app_logger_test.dart" "$SRC/test/logger_trace_test.dart" "$LIB/test/"
```

- [ ] **Step 2: 写独立的 `pubspec.yaml`**

Create `/Users/hao/ai/mobile/logger_utils/pubspec.yaml`（去掉 AutoGLM 字样、去掉 `resolution: workspace`、保留 `publish_to: none`）:

```yaml
name: logger_utils
description: A small Dart logging setup with console + daily-rotated file output, JSON pretty-printing, and call tracing.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.10.0

dependencies:
  logging: ^1.3.0
  path: ^1.9.0

dev_dependencies:
  test: any
  very_good_analysis: ^7.0.0
```

- [ ] **Step 3: 写独立的 `analysis_options.yaml`**

现有的是 `include: ../../analysis_options.yaml`（指向 monorepo 根），独立库要内联根配置内容。Create `/Users/hao/ai/mobile/logger_utils/analysis_options.yaml`:

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/strings.g.dart"
    - "**/build/**"
    - "**/.dart_tool/**"
  errors:
    deprecated_member_use: ignore

linter:
  rules:
    always_put_required_named_parameters_first: false
    always_use_package_imports: false
    avoid_catches_without_on_clauses: false
    avoid_final_parameters: false
    avoid_js_rounded_ints: false
    cascade_invocations: false
    directives_ordering: false
    lines_longer_than_80_chars: false
    omit_local_variable_types: false
    one_member_abstracts: false
    prefer_asserts_with_message: false
    prefer_const_constructors: false
    public_member_api_docs: false
    require_trailing_commas: false
    sort_constructors_first: false
    sort_pub_dependencies: false
    sort_unnamed_constructors_first: false
    unawaited_futures: false
    unnecessary_breaks: false
```

- [ ] **Step 4: 写 `.gitignore`**

Create `/Users/hao/ai/mobile/logger_utils/.gitignore`:

```gitignore
.dart_tool/
build/
.packages
pubspec.lock
*.iml
.idea/
```

- [ ] **Step 5: 解析依赖并跑测试/分析，确认本地全绿（仍是 autoglm- 前缀的原样拷贝）**

```bash
cd /Users/hao/ai/mobile/logger_utils
dart pub get
dart analyze --fatal-infos --fatal-warnings
dart test
```
Expected: `dart pub get` 成功；analyze "No issues found!"；`dart test` 全部通过（现有测试断言 `autoglm-`，此时源码仍是 `autoglm-`，应通过）。

- [ ] **Step 6: 提交（git init 在 Task 4 做，这里只是阶段检查点，无需提交）**

本任务不提交（仓库尚未 `git init`）。确认 Step 5 全绿即完成。

---

### Task 2: 把 `autoglm-` 日志前缀参数化为 `filePrefix`（TDD）

**Files:**
- Modify: `/Users/hao/ai/mobile/logger_utils/lib/app_logger.dart`
- Modify: `/Users/hao/ai/mobile/logger_utils/test/app_logger_test.dart`

- [ ] **Step 1: 先改测试，加自定义前缀用例并把旧断言改到默认前缀 `app-`（此时会失败）**

编辑 `/Users/hao/ai/mobile/logger_utils/test/app_logger_test.dart`：

把现有 "creates log file when logsDir is provided" 用例中的 `f.path.contains('autoglm-')` 改为 `f.path.contains('app-')`：
```dart
    test('creates log file with default "app-" prefix when logsDir provided', () {
      initLogging(logsDir: tempDir.path);
      Logger('test').info('hello');
      final files = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('app-'))
          .toList();
      expect(files, isNotEmpty);
    });
```

把现有 "prunes old log files, keeping most recent 5" 用例改用 `app-` 文件名：
```dart
    test('prunes old log files, keeping most recent 5', () {
      for (var i = 0; i < 7; i++) {
        final file = File('${tempDir.path}/app-2026-01-0$i.log');
        file.writeAsStringSync('log $i');
        file.setLastModifiedSync(DateTime(2026).add(Duration(days: i)));
      }
      initLogging(logsDir: tempDir.path);
      final remaining = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('app-'))
          .toList();
      expect(remaining.length, 5);
    });
```

在 `group('initLogging', ...)` 内新增两个用例：
```dart
    test('uses custom filePrefix for log file names', () {
      initLogging(logsDir: tempDir.path, filePrefix: 'myapp');
      Logger('test').info('hello');
      final files = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('myapp-'))
          .toList();
      expect(files, isNotEmpty);
    });

    test('prune only removes files matching the active prefix', () {
      // 6 files with the active prefix + 2 with a different prefix
      for (var i = 0; i < 6; i++) {
        final f = File('${tempDir.path}/app-2026-02-0$i.log')
          ..writeAsStringSync('x');
        f.setLastModifiedSync(DateTime(2026, 2).add(Duration(days: i)));
      }
      for (var i = 0; i < 2; i++) {
        File('${tempDir.path}/other-2026-02-0$i.log').writeAsStringSync('y');
      }
      initLogging(logsDir: tempDir.path);
      final names = tempDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      // app- pruned to 5, other- untouched
      expect(names.where((n) => n.startsWith('app-')).length, 5);
      expect(names.where((n) => n.startsWith('other-')).length, 2);
    });
```

- [ ] **Step 2: 跑测试，确认新/改用例失败**

```bash
cd /Users/hao/ai/mobile/logger_utils && dart test test/app_logger_test.dart
```
Expected: FAIL —— 默认前缀仍是 `autoglm-`，故 `app-` 相关断言不满足；`filePrefix` 命名参数尚不存在会导致编译错误。

- [ ] **Step 3: 实现 `filePrefix` 参数化**

编辑 `/Users/hao/ai/mobile/logger_utils/lib/app_logger.dart`。

把 `initLogging` 签名与内部调用改为（替换现有 `void initLogging({String? logsDir}) { ... }` 整个函数体中相关行）:
```dart
void initLogging({String? logsDir, String filePrefix = 'app'}) {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = _debugMode ? Level.FINE : Level.INFO;

  final dir = logsDir != null ? Directory(logsDir) : null;
  if (dir != null && !dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  _pruneOldFiles(dir, filePrefix);

  _subscription?.cancel();
  _subscription = Logger.root.onRecord.listen((record) {
    _consoleSink(record);
    _fileSink(record, dir, filePrefix);
  });
}
```

把 `_fileSink` 签名与文件名改为:
```dart
void _fileSink(LogRecord record, Directory? dir, String filePrefix) {
  if (dir == null) return;
  try {
    final today = DateTime.now();
    final fileName = '$filePrefix-${_dateStamp(today)}.log';
```
（其余函数体不变。）

把 `_pruneOldFiles` 签名与匹配前缀改为:
```dart
void _pruneOldFiles(Directory? dir, String filePrefix) {
  if (dir == null || !dir.existsSync()) return;
  try {
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => basename(f.path).startsWith('$filePrefix-'))
            .toList()
```
（其余函数体不变。）

同时把文件顶部文档注释里提到的 `autoglm-YYYY-MM-DD.log` 改为 `<prefix>-YYYY-MM-DD.log`（说明默认 `app`）。

- [ ] **Step 4: 跑测试 + 分析，确认全绿**

```bash
cd /Users/hao/ai/mobile/logger_utils
dart analyze --fatal-infos --fatal-warnings
dart test
```
Expected: analyze "No issues found!"；所有测试通过（含两个新用例）。

- [ ] **Step 5: 提交检查点**

本任务仍不提交（`git init` 在 Task 4）。确认 Step 4 全绿即完成。

---

### Task 3: 补 LICENSE / README / CHANGELOG / CI

**Files:**
- Create: `/Users/hao/ai/mobile/logger_utils/LICENSE`
- Create: `/Users/hao/ai/mobile/logger_utils/README.md`
- Create: `/Users/hao/ai/mobile/logger_utils/CHANGELOG.md`
- Create: `/Users/hao/ai/mobile/logger_utils/.github/workflows/ci.yaml`

- [ ] **Step 1: 写 MIT `LICENSE`**

Create `/Users/hao/ai/mobile/logger_utils/LICENSE`:
```text
MIT License

Copyright (c) 2026 sunbird89629

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: 写 `README.md`**

Create `/Users/hao/ai/mobile/logger_utils/README.md`:
````markdown
# logger_utils

A small Dart logging setup built on [`logging`](https://pub.dev/packages/logging):

- Console sink with colored levels + optional daily-rotated file output (keeps the 5 most recent files)
- `prettyJson` / `Logger.infoJson` for JSON-payload logging
- `Logger.trace` / `traceAsync` for call-site argument/return tracing (FINE level, zero overhead when not loggable)

Pure Dart — works in Flutter, server, and CLI projects.

## Install (git dependency)

```yaml
dependencies:
  logger_utils:
    git:
      url: https://github.com/sunbird89629/logger_utils.git
      ref: v0.1.0
```

## Usage

```dart
import 'package:logger_utils/logger_utils.dart';

void main() {
  // Console only:
  initLogging();

  // With daily-rotated files named `myapp-YYYY-MM-DD.log` under ./logs:
  initLogging(logsDir: 'logs', filePrefix: 'myapp');

  final log = Logger('my.module');
  log.info('started');
  log.infoJson('payload', {'a': 1});
  final n = log.trace('square', [3], () => 3 * 3);
}
```

Levels: `FINE` = debug detail / full payload dumps · `INFO` = key events · `WARNING` = recoverable errors. In debug builds the root level is `FINE`; in release it is `INFO`.

## License

MIT
````

- [ ] **Step 3: 写 `CHANGELOG.md`**

Create `/Users/hao/ai/mobile/logger_utils/CHANGELOG.md`:
```markdown
# Changelog

## 0.1.0

- Initial release: extracted as a standalone library.
- Console + daily-rotated file logging via `initLogging({logsDir, filePrefix})`.
- `prettyJson` / `Logger.infoJson` JSON logging helpers.
- `Logger.trace` / `traceAsync` call tracing.
```

- [ ] **Step 4: 写 GitHub Actions CI**

Create `/Users/hao/ai/mobile/logger_utils/.github/workflows/ci.yaml`:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: dart analyze --fatal-infos --fatal-warnings
      - run: dart test
```

- [ ] **Step 5: 本地确认 format 通过（CI 会跑同样的检查）**

```bash
cd /Users/hao/ai/mobile/logger_utils && dart format --output=none --set-exit-if-changed .
```
Expected: 退出码 0（无需改动）。若有改动，运行 `dart format .` 后再确认。

---

### Task 4: git init、推送 GitHub、打 tag v0.1.0

**Files:** 无新增源码（仅 git 操作）

- [ ] **Step 1: git init 并首次提交**

```bash
cd /Users/hao/ai/mobile/logger_utils
git init -b main
git add .
git commit -m "feat: initial logger_utils standalone library (v0.1.0)

Console + daily-rotated file logging, JSON helpers, call tracing.
Extracted from autoglm_scrcpy_flutter monorepo.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 2: 创建公开 GitHub 仓库并推送**

```bash
cd /Users/hao/ai/mobile/logger_utils
gh repo create sunbird89629/logger_utils --public --source=. --remote=origin --push
```
Expected: 仓库创建成功并推送 `main`。若 `gh` 未登录，提示用户运行 `! gh auth login` 后重试。

- [ ] **Step 3: 打并推送 tag v0.1.0**

```bash
cd /Users/hao/ai/mobile/logger_utils
git tag v0.1.0
git push origin v0.1.0
```
Expected: tag 推送成功。

- [ ] **Step 4: 校验远端 tag 可被解析**

```bash
git ls-remote --tags https://github.com/sunbird89629/logger_utils.git
```
Expected: 输出含 `refs/tags/v0.1.0`。

---

### Task 5: 改造 monorepo —— 删本地包，5 个消费方改 git 依赖

**Files:**
- Delete: `$MONO/packages/logger_utils/`（整个目录）
- Modify: `$MONO/pubspec.yaml`（workspace 列表第 9 行）
- Modify: `$MONO/scrcpy_app/pubspec.yaml`、`$MONO/scrcpy_flutter/pubspec.yaml`、`$MONO/scrcpy_mcp/pubspec.yaml`、`$MONO/scrcpy_plus/pubspec.yaml`、`$MONO/packages/adb_tools/pubspec.yaml`

- [ ] **Step 1: 删除本地包目录并从 workspace 列表移除**

```bash
cd /Users/hao/ai/mobile/asf_dev
git rm -r packages/logger_utils
```

编辑 `$MONO/pubspec.yaml`，删除 workspace 列表中的这一行:
```yaml
  - packages/logger_utils
```

- [ ] **Step 2: 4 个 app 包改 git 依赖**

对 `scrcpy_app/pubspec.yaml`、`scrcpy_flutter/pubspec.yaml`、`scrcpy_mcp/pubspec.yaml`、`scrcpy_plus/pubspec.yaml`，把:
```yaml
  logger_utils:
    path: ../packages/logger_utils
```
改为:
```yaml
  logger_utils:
    git:
      url: https://github.com/sunbird89629/logger_utils.git
      ref: v0.1.0
```

- [ ] **Step 3: adb_tools 改 git 依赖**

编辑 `$MONO/packages/adb_tools/pubspec.yaml`，把:
```yaml
  logger_utils:
    path: ../logger_utils
```
改为:
```yaml
  logger_utils:
    git:
      url: https://github.com/sunbird89629/logger_utils.git
      ref: v0.1.0
```

- [ ] **Step 4: 重新 bootstrap，解析 git 依赖**

```bash
cd /Users/hao/ai/mobile/asf_dev && melos bootstrap
```
Expected: 成功；输出能看到从 git 拉取 `logger_utils`。

- [ ] **Step 5: 全量 analyze + test**

```bash
cd /Users/hao/ai/mobile/asf_dev
melos run analyze
melos run test
```
Expected: analyze 全包 "No issues found!"；`melos run test` 全部通过（证明 git 依赖解析与 API 一致）。

- [ ] **Step 6: 提交**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add -A
git commit -m "refactor: consume logger_utils as a git dependency (extracted to standalone repo)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- 新仓库结构（spec ①）→ Task 1 ✓
- 通用化 filePrefix + pubspec 去 AutoGLM/去 workspace（spec ②）→ Task 2 + Task 1 Step 2 ✓
- LICENSE/README/CHANGELOG/CI（spec ③）→ Task 3 ✓
- monorepo 删包 + 根 pubspec + 5 消费方 git 依赖（spec ④）→ Task 5 ✓
- 实施顺序：先建库→推送打 tag→再 rewire（spec ⑤）→ Task 1-4 在 $LIB，Task 5 在 $MONO，顺序一致 ✓
- 测试：库的现有+filePrefix 用例、CI 三连、monorepo bootstrap+analyze+test（spec ⑥）→ Task 2/3/5 ✓
- 调用点不改（spec 非目标）→ 计划未触碰任何 `initLogging()` 调用点 ✓

**Placeholder scan:** 无 TBD/TODO；新文件均给出完整内容，源/测试文件为原样拷贝（明确命令）。

**Type consistency:** `initLogging({String? logsDir, String filePrefix = 'app'})`、`_fileSink(LogRecord, Directory?, String)`、`_pruneOldFiles(Directory?, String)` 三处签名在 Task 2 内自洽；git 依赖块（url + ref `v0.1.0`）在 Task 5 三步完全一致；tag `v0.1.0` 在 Task 4 创建、Task 5 引用，一致。
