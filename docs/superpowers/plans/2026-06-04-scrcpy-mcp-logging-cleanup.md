# scrcpy_mcp 日志治理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一 `scrcpy_mcp` 包内的 logger 命名、变量名与日志级别，使 release 日志干净、debug 细节齐全。

**Architecture:** 纯重构，无行为变化。logger name 统一为 `scrcpy.mcp.*` 分层 dot 命名；logger 变量统一为 `_log`；删除死代码 `moduleLogger`；把整段 payload 转储从 INFO 降到 FINE，工具调用审计行截断 args 后保留 INFO。

**Tech Stack:** Dart, `logging` 包, melos 工作区。

**测试策略说明:** 无任何测试断言生产日志的级别或内容（仅 `test/phone_agent_test/youtube_history_test.dart` 用了它自己的 `youtube.history` logger）。因此本计划不新增针对日志行的脆弱测试，验证手段为 `melos run analyze`（`--fatal-infos --fatal-warnings`）+ `melos run test` 全绿。所有命令在仓库根 `/Users/hao/ai/mobile/asf_dev` 执行。

---

### Task 1: 统一 logger 命名与变量名，删除死代码

**Files:**
- Modify: `scrcpy_mcp/bin/scrcpy_mcp.dart:9`
- Modify: `scrcpy_mcp/lib/src/mcp_tool.dart:5,27,33,39,41`
- Modify: `scrcpy_mcp/lib/src/recording_controller.dart:7`
- Modify: `scrcpy_mcp/lib/src/agent/phone_agent.dart:8`

- [ ] **Step 1: 删除 bin 中的死代码 `moduleLogger`**

`scrcpy_mcp/bin/scrcpy_mcp.dart` 第 9 行定义后全项目无人调用。删除该行及其后的空行，使第 7 行 import 之后直接空一行接 `void main`。保留 `import 'package:logger_utils/logger_utils.dart';`（`initLogging()` 仍需要）。

删除：
```dart
final moduleLogger = Logger('scrcpy_mcp');
```

- [ ] **Step 2: 重命名 `mcp_tool.dart` 的 logger 与变量**

`scrcpy_mcp/lib/src/mcp_tool.dart`：

第 5 行：
```dart
final _baseLogger = Logger('scrcpy.mcp');
```
改为：
```dart
final _log = Logger('scrcpy.mcp.tool');
```

第 27 行：
```dart
  Logger get logger => _baseLogger;
```
改为：
```dart
  Logger get logger => _log;
```

第 33 行 `_baseLogger.info('$name ← $args');` → `_log.info('$name ← $args');`
第 39 行 `_baseLogger.warning('$name → ${ms}ms | ERROR | $summary');` → `_log.warning('$name → ${ms}ms | ERROR | $summary');`
第 41 行 `_baseLogger.info('$name → ${ms}ms | $summary');` → `_log.info('$name → ${ms}ms | $summary');`

（注意：本任务只做改名，args 截断在 Task 2 处理。）

- [ ] **Step 3: 修正 `recording_controller.dart` 的 logger name**

`scrcpy_mcp/lib/src/recording_controller.dart` 第 7 行：
```dart
final _log = Logger('scrcpy.recording');
```
改为：
```dart
final _log = Logger('scrcpy.mcp.recording');
```

- [ ] **Step 4: 修正 `phone_agent.dart` 的 logger name**

`scrcpy_mcp/lib/src/agent/phone_agent.dart` 第 8 行：
```dart
final _log = Logger('PhoneAgent');
```
改为：
```dart
final _log = Logger('scrcpy.mcp.agent');
```

- [ ] **Step 5: 运行 analyze 确认无错**

Run: `cd /Users/hao/ai/mobile/asf_dev && melos run analyze`
Expected: PASS，无 error/warning/info。

- [ ] **Step 6: 运行测试确认无回归**

Run: `cd /Users/hao/ai/mobile/asf_dev && melos run test`
Expected: 全部测试通过。

- [ ] **Step 7: 提交**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_mcp/bin/scrcpy_mcp.dart scrcpy_mcp/lib/src/mcp_tool.dart scrcpy_mcp/lib/src/recording_controller.dart scrcpy_mcp/lib/src/agent/phone_agent.dart
git commit -m "refactor(scrcpy_mcp): unify logger names to scrcpy.mcp.* and var to _log

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 级别治理（整段转储降 FINE，审计行截断 args）

**Files:**
- Modify: `scrcpy_mcp/lib/src/agent/phone_agent.dart:108,125,268`
- Modify: `scrcpy_mcp/lib/src/mcp_tool.dart:33`

- [ ] **Step 1: phone_agent 把完整 LLM rawText 降到 FINE**

`scrcpy_mcp/lib/src/agent/phone_agent.dart`：

第 108 行 `_log.info('rawText:$rawText');` → `_log.fine('rawText:$rawText');`
第 125 行 `_log.info('rawText(retry):$rawText');` → `_log.fine('rawText(retry):$rawText');`

第 115 行的截断重试提示 `_log.info('output truncated (length); retrying with a concise nudge');` **保持 info 不变**（稀疏关键信号）。

- [ ] **Step 2: phone_agent 把每条消息 toLog() 降到 FINE**

`scrcpy_mcp/lib/src/agent/phone_agent.dart` 第 268 行（`MessageList.add` 内）：
```dart
    _log.info(value.toLog());
```
改为：
```dart
    _log.fine(value.toLog());
```

- [ ] **Step 3: mcp_tool 入口审计行截断 args**

`scrcpy_mcp/lib/src/mcp_tool.dart` 第 33 行（Task 1 后已是 `_log.info`）：
```dart
    _log.info('$name ← $args');
```
改为（复用同类已有的静态 `truncate`，类内可不带类名直接调用）：
```dart
    _log.info('$name ← ${truncate(args.toString(), 200)}');
```

- [ ] **Step 4: 运行 analyze 确认无错**

Run: `cd /Users/hao/ai/mobile/asf_dev && melos run analyze`
Expected: PASS，无 error/warning/info。

- [ ] **Step 5: 运行测试确认无回归**

Run: `cd /Users/hao/ai/mobile/asf_dev && melos run test`
Expected: 全部测试通过。

- [ ] **Step 6: 提交**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_mcp/lib/src/agent/phone_agent.dart scrcpy_mcp/lib/src/mcp_tool.dart
git commit -m "refactor(scrcpy_mcp): demote payload dumps to FINE, truncate tool-call args

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- 命名统一（设计 ①）→ Task 1 Step 2/3/4 ✓
- 删 `moduleLogger` 死代码（设计 ①）→ Task 1 Step 1 ✓
- 变量名统一 `_log`（设计 ②）→ Task 1 Step 2 ✓
- rawText / toLog 降 FINE（设计 ③）→ Task 2 Step 1/2 ✓
- 重试提示保留 info（设计 ③）→ Task 2 Step 1 显式保留 ✓
- args 截断（设计 ③）→ Task 2 Step 3 ✓
- 验证 analyze + test（设计 ④）→ 两个 Task 各含 ✓

**Placeholder scan:** 无 TBD/TODO，每个改动都给出确切前后代码。

**Type consistency:** 变量统一为 `_log`；`truncate` 为 `McpTool` 已存在的静态方法 `static String truncate(String s, int maxLen)`，签名与调用一致。
