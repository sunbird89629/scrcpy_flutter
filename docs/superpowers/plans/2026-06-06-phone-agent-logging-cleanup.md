# PhoneAgent 日志清理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 agent 运行日志从「重复 + 装饰噪音」整理为两档结构：INFO 给每步可扫读索引（`task:` / `step N 动作` / `step N → 结果`），FINE 给单份全文推理 + 一行 ADB。

**Architecture:** 在 `PhoneAgent.run` 内显式分级打日志，删掉重复来源（`_requestAction` 的 `rawText` 日志 + `MessageList` 盲打日志），`MessageList` 类一并移除、`messages` 改回普通 `List<LlmMessage>`。新增纯函数 `actionSummary` 渲染动作摘要。共享包 `adb_tools` 的 5 行 `>>>>` 框压成一行可单测的 `formatResultLine`。

**Tech Stack:** Dart（纯 Dart 包，`package:test`），melos 工作区，`logger_utils`（不改）。

参考 spec：`docs/superpowers/specs/2026-06-06-phone-agent-logging-cleanup-design.md`

**注意：** `scrcpy_mcp/lib/src/agent/phone_agent.dart` 当前工作区有一处用户未提交的小改动（`final trimedHistory = _trimHistory(messages);` 抽变量，第 170 行），本计划基于该现状，不要回退它。

---

## Task 1: adb_tools —— ADB 日志压成一行（`formatResultLine`）

**Files:**
- Modify: `packages/adb_tools/lib/src/adb_process_runner.dart`
- Test: `packages/adb_tools/test/adb_process_runner_test.dart`

**Work from:** `packages/adb_tools`

- [ ] **Step 1: 写失败测试**

在 `packages/adb_tools/test/adb_process_runner_test.dart` 顶部把 import 改为含 `dart:io`（用于 `ProcessResult`），并在 `main()` 内、`group('AdbProcessRunnerImpl', ...)` 之后追加一个新 group。最终文件 import 区与新 group 如下（其余既有测试保留不动）：

文件第 1–3 行改为：
```dart
import 'dart:io';

import 'package:adb_tools/src/adb_process_runner.dart';
import 'package:adb_tools/src/exceptions.dart';
import 'package:test/test.dart';
```

在 `main()` 的最外层（与 `group('AdbProcessRunnerImpl', ...)` 同级）追加：
```dart
  group('AdbProcessRunnerImpl.formatResultLine', () {
    test('success without stderr → single line with exit code', () {
      final r = ProcessResult(123, 0, 'ok', '');
      expect(
        AdbProcessRunnerImpl.formatResultLine('adb shell input tap 1 2', r),
        'adb shell input tap 1 2 → exit 0',
      );
    });

    test('non-empty stderr is appended', () {
      final r = ProcessResult(123, 1, '', 'boom');
      expect(
        AdbProcessRunnerImpl.formatResultLine('adb x', r),
        'adb x → exit 1 | stderr: boom',
      );
    });

    test('no decorative block or ProcessResult dump', () {
      final line = AdbProcessRunnerImpl.formatResultLine(
        'cmd',
        ProcessResult(1, 0, '', ''),
      );
      expect(line, isNot(contains('>>>>')));
      expect(line, isNot(contains('Instance of')));
      expect(line.split('\n'), hasLength(1));
    });
  });
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `dart test test/adb_process_runner_test.dart -N formatResultLine`
Expected: FAIL —— `AdbProcessRunnerImpl.formatResultLine` 未定义（编译错误）。

- [ ] **Step 3: 实现一行格式**

在 `packages/adb_tools/lib/src/adb_process_runner.dart` 中：

(a) 把 `run()` 里这一行：
```dart
      _log.fine(_formatResult([executable, ...arguments].join(' '), result));
```
改为：
```dart
      _log.fine(formatResultLine([executable, ...arguments].join(' '), result));
```

(b) 把整个 `_formatResult` 方法：
```dart
  static String _formatResult(String command, ProcessResult r) {
    final buf = StringBuffer();
    buf.writeln();
    buf.writeln('>' * 20);
    buf.writeln('command:$command');
    buf.writeln('result:$r');
    buf.writeln('<' * 20);
    return buf.toString();
  }
```
替换为：
```dart
  /// One-line FINE log of a finished ADB process: `<command> → exit <code>`,
  /// with stderr appended when non-empty. Package-internal (lives in `src/`,
  /// not exported) but non-private so it can be unit-tested directly.
  static String formatResultLine(String command, ProcessResult r) {
    final stderr = (r.stderr as Object?)?.toString().trim() ?? '';
    return stderr.isEmpty
        ? '$command → exit ${r.exitCode}'
        : '$command → exit ${r.exitCode} | stderr: $stderr';
  }
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `dart test test/adb_process_runner_test.dart`
Expected: PASS（含既有 4 个 run 测试 + 3 个 formatResultLine 测试）。

- [ ] **Step 5: 分析**

Run: `dart analyze --fatal-infos --fatal-warnings`
Expected: No issues found.

- [ ] **Step 6: 提交**

```bash
git add packages/adb_tools/lib/src/adb_process_runner.dart packages/adb_tools/test/adb_process_runner_test.dart
git commit -m "refactor(adb_tools): collapse ADB result log to one testable line

Replace the 5-line >>>> block + useless ProcessResult dump with
formatResultLine: '<command> → exit <code>' (+ stderr when present)."
```

---

## Task 2: PhoneAgent —— 两档日志 + 去重 + 移除 MessageList

**Files:**
- Modify: `scrcpy_mcp/lib/src/agent/phone_agent.dart`
- Modify: `scrcpy_mcp/lib/src/agent/llm_client.dart`
- Test: `scrcpy_mcp/test/phone_agent_test.dart`

**Work from:** `scrcpy_mcp`

- [ ] **Step 1: 写 `actionSummary` 失败测试**

在 `scrcpy_mcp/test/phone_agent_test.dart` 的 `main()` 内最外层追加一个 group（`actionSummary` 经 barrel `package:scrcpy_mcp/scrcpy_mcp.dart` 导出，文件已 import 该 barrel）：

```dart
  group('actionSummary', () {
    test('Tap shows coordinates', () {
      expect(
        actionSummary(const DoAction(action: 'Tap', element: [897, 939])),
        'Tap(897,939)',
      );
    });

    test('Swipe shows start→end', () {
      expect(
        actionSummary(
          const DoAction(action: 'Swipe', start: [499, 702], end: [499, 263]),
        ),
        'Swipe(499,702→499,263)',
      );
    });

    test('Wait shows the raw duration', () {
      expect(
        actionSummary(const DoAction(action: 'Wait', duration: '2 seconds')),
        'Wait(2 seconds)',
      );
    });

    test('Launch shows the app', () {
      expect(
        actionSummary(const DoAction(action: 'Launch', app: 'Chrome')),
        'Launch(Chrome)',
      );
    });

    test('Type shows quoted text', () {
      expect(
        actionSummary(const DoAction(action: 'Type', text: '张三')),
        'Type("张三")',
      );
    });

    test('long text is truncated with an ellipsis', () {
      final s = actionSummary(DoAction(action: 'Type', text: '一' * 30));
      expect(s, startsWith('Type("'));
      expect(s, contains('…'));
    });

    test('Back renders without parens', () {
      expect(actionSummary(const DoAction(action: 'Back')), 'Back');
    });

    test('Note shows its message', () {
      expect(
        actionSummary(const DoAction(action: 'Note', message: 'True')),
        'Note("True")',
      );
    });

    test('Finish shows quoted message', () {
      expect(actionSummary(const FinishAction('done')), 'Finish("done")');
    });
  });
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `dart test test/phone_agent_test.dart -N actionSummary`
Expected: FAIL —— `actionSummary` 未定义（编译错误）。

- [ ] **Step 3: 实现 `actionSummary` 与 `_indent`（顶层函数）**

在 `scrcpy_mcp/lib/src/agent/phone_agent.dart` 文件末尾（`class PhoneAgent` 之后、原 `MessageList` 类的位置）加入两个顶层函数，并在下一步删掉 `MessageList`：

```dart
/// A compact one-line rendering of [action] for the INFO step-index log,
/// e.g. `Tap(897,939)`, `Swipe(499,702→499,263)`, `Wait(2 seconds)`.
String actionSummary(PhoneAction action) {
  String quote(String s) {
    const max = 20;
    final flat = s.replaceAll('\n', ' ');
    final clipped = flat.length > max ? '${flat.substring(0, max)}…' : flat;
    return '"$clipped"';
  }

  switch (action) {
    case FinishAction(:final message):
      return 'Finish(${quote(message)})';
    case DoAction():
      String coord(List<int>? p) => p == null ? '?' : '${p[0]},${p[1]}';
      switch (action.action) {
        case 'Tap':
        case 'Long Press':
        case 'Double Tap':
          return '${action.action}(${coord(action.element)})';
        case 'Swipe':
          return 'Swipe(${coord(action.start)}→${coord(action.end)})';
        case 'Type':
        case 'Type_Name':
          return '${action.action}(${quote(action.text ?? '')})';
        case 'Launch':
          return 'Launch(${action.app ?? '?'})';
        case 'Wait':
          return 'Wait(${action.duration ?? '?'})';
        default:
          // Back / Home / Interact / Take_over / Note / Call_API …
          return action.message == null
              ? action.action
              : '${action.action}(${quote(action.message!)})';
      }
  }
}

/// Indents every line of [text] by two spaces for the FINE `reply:` block.
String _indent(String text) =>
    text.trim().split('\n').map((line) => '  $line').join('\n');
```

- [ ] **Step 4: 运行 `actionSummary` 测试，确认通过**

Run: `dart test test/phone_agent_test.dart -N actionSummary`
Expected: PASS（9 个 actionSummary 测试）。

- [ ] **Step 5: 重构 `run()` 的日志与控制流**

在 `phone_agent.dart` 的 `run()` 中：

(a) 方法体最前面加任务日志。把：
```dart
  Future<AgentResult> run(String message) async {
    final messages = _buildInitialMessages();
```
改为：
```dart
  Future<AgentResult> run(String message) async {
    _log.info('task: $message');
    final messages = _buildInitialMessages();
```

(b) 把 `switch (parsed) { ... }` 整块替换为（加入 INFO 索引行、FINE 全文 reply、结果行；去掉重复来源）：
```dart
      switch (parsed) {
        case ParseFailure(:final reason, :final content):
          // Completion goes through finish(...), which the parser recognizes.
          // A failure here means the output format broke — report it rather
          // than masquerading a format error as success.
          _log.warning('step $step parse failed: $reason');
          _log.fine('reply(unparsed):\n${_indent(content)}');
          return AgentResult(
            result: 'Could not parse an action ($reason): ${content.trim()}',
            steps: step + 1,
            success: false,
          );
        case ParsedAction(:final action, :final content):
          _log.info('step $step  ${actionSummary(action)}');
          _log.fine('reply:\n${_indent(content)}');
          // Record the assistant turn (content already excludes <think>).
          messages.add(LlmMessage(role: 'assistant', textContent: content));
          final outcome = await _dispatchAction(
            action,
            step,
            lastActionSig: lastActionSig,
            repeatedActions: repeatedActions,
          );
          final resultText =
              outcome.done?.result ?? outcome.result ?? '(no result)';
          _log.info('step $step → $resultText');
          if (outcome.done != null) return outcome.done!;
          lastResult = outcome.result;
          lastActionSig = outcome.sig;
          repeatedActions = outcome.repeats;
      }
```

- [ ] **Step 6: 删掉 `_requestAction` 里的 rawText 日志**

在 `_requestAction` 中删除这两行（保留 `_log.info('output truncated ...')` 那行）：
```dart
    _log.fine('rawText:${response.text}');
```
和
```dart
      _log.fine('rawText(retry):${response.text}');
```

- [ ] **Step 7: 移除 `MessageList`，`messages` 改回普通 `List<LlmMessage>`**

(a) 删除文件末尾整个 `MessageList` 类：
```dart
class MessageList extends DelegatingList<LlmMessage> {
  MessageList(super.base);
  @override
  void add(LlmMessage value) {
    _log.fine(value.toLog());
    super.add(value);
  }
}
```

(b) 删除第 1 行不再需要的 import：
```dart
import 'package:collection/collection.dart';
```

(c) `_buildInitialMessages` 返回类型与返回值改为普通 List。把：
```dart
  MessageList _buildInitialMessages() {
```
改为：
```dart
  List<LlmMessage> _buildInitialMessages() {
```
并把它的 `return`：
```dart
    return MessageList(<LlmMessage>[
      LlmMessage(role: 'system', textContent: systemPrompt),
    ]);
```
改为：
```dart
    return <LlmMessage>[
      LlmMessage(role: 'system', textContent: systemPrompt),
    ];
```

(d) `_requestAction` 形参类型 `MessageList messages` 改为 `List<LlmMessage> messages`：
```dart
  Future<ParsedResponse> _requestAction(
    List<LlmMessage> messages, {
```

- [ ] **Step 8: 删除 `llm_client.dart` 中不再使用的 `toLog`**

在 `scrcpy_mcp/lib/src/agent/llm_client.dart` 删除（其唯一调用方 `MessageList` 已移除）：
```dart
  String toLog() {
    return '$role:$textContent';
  }
```

- [ ] **Step 9: 跑全套 scrcpy_mcp 单测**

Run: `dart test test/phone_agent_test.dart test/response_parser_test.dart`
Expected: PASS。重点确认仍通过：`strips <think> blocks from assistant history`（assistant 历史 = content，逻辑未变）、`keeps only the last keepScreenshots screenshots in history`（`messages` 改普通 List 不影响）、`returns failure when LLM output has no parseable action`、`retries once on a truncated (length) response`，以及新增的 `actionSummary` 组。

- [ ] **Step 10: 分析**

Run: `dart analyze --fatal-infos --fatal-warnings`
Expected: No issues found（特别是不再有未使用的 `collection` import / `MessageList` / `toLog` / `DelegatingList` 引用）。

- [ ] **Step 11: 提交**

```bash
git add scrcpy_mcp/lib/src/agent/phone_agent.dart scrcpy_mcp/lib/src/agent/llm_client.dart scrcpy_mcp/test/phone_agent_test.dart
git commit -m "refactor(agent): two-tier logging, drop dup reply logs and MessageList

INFO: task + per-step action index + result. FINE: single full reply +
one-line adb. Remove the rawText logs and the MessageList blanket logger
(messages → plain List); add actionSummary; drop now-dead LlmMessage.toLog."
```

---

## 完成标准

- 每步日志：INFO `task:` 一次、`step N <动作摘要>`、`step N → <结果>`；FINE 单份 `reply:` 全文 + 一行 `<cmd> → exit N`。
- 模型回复不再被打两遍；user 反馈行、系统提示词不再单独打印；ADB 无 `>>>>` 框。
- `MessageList`、`LlmMessage.toLog`、`collection` import 均已移除。
- `actionSummary` 与 `formatResultLine` 有单测；既有行为测试无回归。
- `dart analyze --fatal-infos --fatal-warnings` 干净，`dart test` 相关文件全绿。
