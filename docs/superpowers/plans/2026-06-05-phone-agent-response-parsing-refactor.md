# PhoneAgent 响应解析重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 autoglm-phone 响应解析从 `PhoneAgent` 抽出为一个返回 sealed `ParsedResponse` 的 `ResponseParser`，消除散落的 `<think>` 正则与 `null` 语义歧义，并精简到实际需要的 `do()`/`finish()` 两种格式。

**Architecture:** 新增 `ResponseParser.parse(String) → ParsedResponse`（`ParsedAction` / `ParseFailure`，基类含 `think`/`content`），两段式：先拆 `<think>`/`<answer>` 得到 `content`，再识别 `do()`/`finish()`。自由文本字段用 `indexOf` 提取以容忍未转义引号。`PhoneAgent` 改为对结果 `switch`，不再含正则。分三个保持「每次提交可编译且测试通过」的任务推进。

**Tech Stack:** Dart（纯 Dart 包，`package:test`），melos 工作区。

参考设计 spec：`docs/superpowers/specs/2026-06-05-phone-agent-response-parsing-refactor-design.md`

**命令约定**（均在 `scrcpy_mcp/` 目录下执行，即当前工作目录）：
- 跑单个测试文件：`dart test test/<file>.dart`
- 静态分析：`dart analyze`

---

## Task 1: 新增 `ResponseParser` 与 `ParsedResponse`（加法，不破坏旧代码）

本任务只**新增** `response_parser.dart` 和它的测试，`PhoneAction` 暂时仍从旧的 `action_parser.dart` 导入（并 re-export），旧的 `ActionParser` 原封不动。因此全包仍可编译、旧测试仍通过。

**Files:**
- Create: `lib/src/agent/response_parser.dart`
- Create: `test/response_parser_test.dart`

- [ ] **Step 1: 写解析器（先写实现，因为测试需要引用类型）**

Create `lib/src/agent/response_parser.dart`:

```dart
import 'action_parser.dart';

// PhoneAction 类型暂留在 action_parser.dart，Task 3 再迁入本文件。
export 'action_parser.dart' show PhoneAction, DoAction, FinishAction;

/// Structured result of parsing one autoglm-phone model reply.
sealed class ParsedResponse {
  const ParsedResponse({required this.think, required this.content});

  /// Reasoning captured inside `<think></think>`, or '' when absent.
  final String think;

  /// Everything outside the `<think></think>` block: any untagged reasoning
  /// plus the action token. This is what gets stored in assistant history.
  final String content;
}

/// A parseable action was found.
final class ParsedAction extends ParsedResponse {
  const ParsedAction({
    required super.think,
    required super.content,
    required this.action,
  });

  final PhoneAction action;
}

/// No usable action could be parsed; [reason] explains why.
final class ParseFailure extends ParsedResponse {
  const ParseFailure({
    required super.think,
    required super.content,
    required this.reason,
  });

  final String reason;
}

/// Parses autoglm-phone model output into a [ParsedResponse].
///
/// The model emits `<think>…</think>` reasoning followed by exactly one action:
/// `do(action="…", …)` or `finish(message="…")`, optionally wrapped in
/// `<answer>…</answer>` and possibly preceded by natural-language text.
class ResponseParser {
  static ParsedResponse parse(String text) {
    final (think, content) = _split(text);

    if (content.trim().isEmpty) {
      return ParseFailure(
        think: think,
        content: content,
        reason: 'empty/think-only response',
      );
    }

    // finish(message="…") — matched greedily up to the final `")` so unescaped
    // inner quotes in the message don't truncate it.
    final finishMatch = RegExp(
      r'finish\s*\(\s*message\s*=\s*"(.*)"\s*\)',
      dotAll: true,
    ).firstMatch(content);
    if (finishMatch != null) {
      return ParsedAction(
        think: think,
        content: content,
        action: FinishAction(_unescape(finishMatch.group(1)!)),
      );
    }

    // do(action="…", …)
    final hasDo = RegExp(
      r'do\s*\(\s*action\s*=',
      dotAll: true,
    ).hasMatch(content);
    if (hasDo) {
      final action = _parseDo(content);
      if (action == null) {
        return ParseFailure(
          think: think,
          content: content,
          reason: 'malformed do(): could not extract action type',
        );
      }
      return ParsedAction(think: think, content: content, action: action);
    }

    return ParseFailure(
      think: think,
      content: content,
      reason: 'no action token',
    );
  }

  /// Splits the raw reply into `(think, content)`: pulls the `<think></think>`
  /// block out as [think] and, if present, unwraps `<answer></answer>` in the
  /// remainder. [content] is the remainder with the think block removed.
  static (String think, String content) _split(String text) {
    var think = '';
    final thinkMatch = RegExp(
      r'<think>(.*?)</think>',
      dotAll: true,
    ).firstMatch(text);
    if (thinkMatch != null) think = thinkMatch.group(1)!.trim();

    var content = text.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true),
      '',
    );

    final answerMatch = RegExp(
      r'<answer>\s*(.*?)\s*</answer>',
      dotAll: true,
    ).firstMatch(content);
    if (answerMatch != null) content = answerMatch.group(1)!;

    return (think, content.trim());
  }

  /// Parses the inside of a `do(...)` call into a [DoAction], or null if the
  /// action type is missing. Coordinate fields use a numeric regex; free-text
  /// fields use [_extractFreeText] to tolerate unescaped quotes.
  static DoAction? _parseDo(String content) {
    final action = _extractQuoted(content, 'action');
    if (action == null) return null;
    return DoAction(
      action: action,
      element: _extractIntList(content, 'element'),
      start: _extractIntList(content, 'start'),
      end: _extractIntList(content, 'end'),
      text: _extractFreeText(content, 'text'),
      app: _extractFreeText(content, 'app'),
      duration: _extractQuoted(content, 'duration'),
      // Call_API carries its payload under `instruction`; fold it into message
      // so the runner has a single field to read.
      message: _extractFreeText(content, 'message') ??
          _extractFreeText(content, 'instruction'),
    );
  }

  /// Extracts a short, well-formed quoted value (`key="value"`), honoring
  /// backslash escapes. Used for `action` and `duration`.
  static String? _extractQuoted(String content, String key) {
    final match = RegExp(
      '$key\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"',
    ).firstMatch(content);
    return match != null ? _unescape(match.group(1)!) : null;
  }

  /// Extracts a free-text field: everything after `key="` to the end of the
  /// call, stripping a trailing `")` (or lone `"`). Assumes the free-text field
  /// is the last argument of the `do(...)` call (true for autoglm output), which
  /// lets unescaped inner quotes pass through unharmed. Returns null if absent.
  static String? _extractFreeText(String content, String key) {
    final marker = '$key="';
    final idx = content.indexOf(marker);
    if (idx == -1) return null;
    var rest = content.substring(idx + marker.length).trimRight();
    if (rest.endsWith('")')) {
      rest = rest.substring(0, rest.length - 2);
    } else if (rest.endsWith('"')) {
      rest = rest.substring(0, rest.length - 1);
    }
    return _unescape(rest);
  }

  static List<int>? _extractIntList(String content, String key) {
    final match =
        RegExp('$key\\s*=\\s*\\[([^\\]]*)\\]').firstMatch(content);
    if (match == null) return null;
    return match
        .group(1)!
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
  }

  static String _unescape(String s) =>
      s.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
}
```

- [ ] **Step 2: 写解析器测试**

Create `test/response_parser_test.dart`:

```dart
import 'package:scrcpy_mcp/src/agent/response_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ResponseParser', () {
    DoAction expectDo(String text) {
      final parsed = ResponseParser.parse(text);
      expect(parsed, isA<ParsedAction>());
      final action = (parsed as ParsedAction).action;
      expect(action, isA<DoAction>());
      return action as DoAction;
    }

    FinishAction expectFinish(String text) {
      final parsed = ResponseParser.parse(text);
      expect(parsed, isA<ParsedAction>());
      final action = (parsed as ParsedAction).action;
      expect(action, isA<FinishAction>());
      return action as FinishAction;
    }

    test('parses do() with keyword args', () {
      final a = expectDo('do(action="Tap", element=[500, 300])');
      expect(a.action, 'Tap');
      expect(a.element, [500, 300]);
    });

    test('parses finish()', () {
      final f = expectFinish('finish(message="All done")');
      expect(f.message, 'All done');
    });

    test('finish() tolerates unescaped inner quotes', () {
      const content =
          '否，界面上没有出现"Twitter（X）的主页"。\n'
          'finish(message="否，界面上没有出现"Twitter（X）的主页"。")';
      final f = expectFinish(content);
      expect(f.message, startsWith('否，界面上没有出现'));
      expect(f.message, isNot(contains('message=')));
      expect(f.message, contains('"Twitter（X）的主页"'));
    });

    test('do() free-text field tolerates unescaped inner quotes', () {
      final a = expectDo('do(action="Type", text="他说"你好"")');
      expect(a.action, 'Type');
      expect(a.text, '他说"你好"');
    });

    test('parses inside <answer> tags', () {
      final a = expectDo('<answer>do(action="Tap", element=[100, 200])</answer>');
      expect(a.action, 'Tap');
      expect(a.element, [100, 200]);
    });

    test('tolerates natural-language prefix before the action', () {
      final a = expectDo('Let me tap it.\ndo(action="Back")');
      expect(a.action, 'Back');
    });

    test('splits <think> into think, keeps the rest as content', () {
      final parsed = ResponseParser.parse(
        '<think>冗长推理</think>do(action="Tap", element=[1, 2])',
      );
      expect(parsed, isA<ParsedAction>());
      expect(parsed.think, '冗长推理');
      expect(parsed.content, isNot(contains('<think>')));
      expect(parsed.content, isNot(contains('冗长推理')));
      expect(parsed.content, contains('do(action'));
    });

    test('parses Call_API instruction into message', () {
      final a = expectDo('do(action="Call_API", instruction="总结当前页面")');
      expect(a.action, 'Call_API');
      expect(a.message, '总结当前页面');
    });

    test('parses sensitive Tap with message', () {
      final a = expectDo('do(action="Tap", element=[10, 20], message="重要操作")');
      expect(a.action, 'Tap');
      expect(a.element, [10, 20]);
      expect(a.message, '重要操作');
    });

    test('ParseFailure on empty response', () {
      final parsed = ResponseParser.parse('');
      expect(parsed, isA<ParseFailure>());
      expect((parsed as ParseFailure).reason, contains('empty'));
    });

    test('ParseFailure on think-only response', () {
      final parsed = ResponseParser.parse('<think>只有推理没有动作</think>');
      expect(parsed, isA<ParseFailure>());
      expect((parsed as ParseFailure).reason, contains('empty'));
    });

    test('ParseFailure on prose with no action token', () {
      final parsed = ResponseParser.parse('这是一段没有任何动作的普通文本');
      expect(parsed, isA<ParseFailure>());
      expect((parsed as ParseFailure).reason, contains('no action token'));
    });

    test('ParseFailure on malformed do() missing action', () {
      final parsed = ResponseParser.parse('do(element=[1,2])');
      expect(parsed, isA<ParseFailure>());
      expect((parsed as ParseFailure).reason, contains('malformed do()'));
    });
  });
}
```

- [ ] **Step 3: 跑测试，确认通过**

Run: `dart test test/response_parser_test.dart`
Expected: 所有 ResponseParser 测试 PASS。

- [ ] **Step 4: 确认旧测试与分析未受影响**

Run: `dart test test/phone_agent_test.dart && dart analyze --fatal-infos --fatal-warnings`
Expected: 旧测试全 PASS，`dart analyze --fatal-infos --fatal-warnings` 无 error（`response_parser.dart` 与 `action_parser.dart` 并存）。

- [ ] **Step 5: 提交**

```bash
git add scrcpy_mcp/lib/src/agent/response_parser.dart scrcpy_mcp/test/response_parser_test.dart
git commit -m "feat(agent): add ResponseParser returning sealed ParsedResponse

Two-stage parse (think/answer split + do/finish), free-text fields use
indexOf extraction to tolerate unescaped quotes. Additive; ActionParser
still in place."
```

---

## Task 2: `PhoneAgent` 改用 `ResponseParser`

把 `PhoneAgent` 切到新解析器：`_requestAction` 返回 `ParsedResponse`，`run()` 改 `switch`，删除 `_appendAssistantHistory` 与 `<think>` 正则、空响应/`null` 特判。删除已失效的简写格式 PhoneAgent 测试。`ActionParser` 仍保留（Task 3 删），全包仍编译。

**Files:**
- Modify: `lib/src/agent/phone_agent.dart`
- Modify: `test/phone_agent_test.dart`

- [ ] **Step 1: 改 import**

In `lib/src/agent/phone_agent.dart`, 把第 4 行：

```dart
import 'action_parser.dart';
```

改为：

```dart
import 'response_parser.dart';
```

（`response_parser.dart` 已 re-export `PhoneAction`/`DoAction`/`FinishAction`，故 `_dispatchAction` 等对这些类型的引用不受影响。）

- [ ] **Step 2: 重写 `_requestAction` 返回 `ParsedResponse`**

In `lib/src/agent/phone_agent.dart`, 用下面整体替换现有的 `_requestAction` 方法（含其 doc 注释）：

```dart
  /// Sends a user turn (text + screenshot) and parses the model's reply into a
  /// [ParsedResponse]. On a truncated response (finish_reason="length", usually
  /// repetition garbage with no parsable action) it retries once asking for a
  /// single concise action before giving up. Mutates [messages] with the turns
  /// it sends.
  Future<ParsedResponse> _requestAction(
    MessageList messages, {
    required String userContent,
    required ({String base64, String mimeType}) screenshot,
  }) async {
    messages.add(
      LlmMessage(
        role: 'user',
        textContent: userContent,
        imageBase64: screenshot.base64,
        imageMimeType: screenshot.mimeType,
      ),
    );
    var response = await llmClient.chat(messages: _trimHistory(messages));
    _log.fine('rawText:${response.text}');
    var parsed = ResponseParser.parse(response.text ?? '');

    if (parsed is ParseFailure && response.finishReason == 'length') {
      _log.info('output truncated (length); retrying with a concise nudge');
      messages.add(
        const LlmMessage(
          role: 'user',
          textContent:
              '上次输出过长被截断。请只输出一个动作指令（如 do(action="Tap", element=[x,y]) 或 finish(message="...")），不要输出任何多余内容。',
        ),
      );
      response = await llmClient.chat(messages: _trimHistory(messages));
      _log.fine('rawText(retry):${response.text}');
      parsed = ResponseParser.parse(response.text ?? '');
    }
    return parsed;
  }
```

- [ ] **Step 3: 重写 `run()` 循环中的第 2–3 步**

In `lib/src/agent/phone_agent.dart`, `run()` 中从 `// 2. Ask the model...` 到第 3 步分发结束（即原本 `final reply = await _requestAction(...)` 一直到 `repeatedActions = outcome.repeats;` 这一整段），整体替换为：

```dart
      // 2. Ask the model for the next action (handles truncation retry).
      final userContent = _buildUserContent(step, message, lastResult);
      final parsed = await _requestAction(
        messages,
        userContent: userContent,
        screenshot: screenshot,
      );

      switch (parsed) {
        case ParseFailure(:final reason, :final content):
          // Completion goes through finish(...), which the parser recognizes.
          // A failure here means the output format broke — report it rather
          // than masquerading a format error as success.
          return AgentResult(
            result: 'Could not parse an action ($reason): ${content.trim()}',
            steps: step + 1,
            success: false,
          );
        case ParsedAction(:final action, :final content):
          // 3. Record the assistant turn (content already excludes the
          // <think> block), then dispatch the action.
          messages.add(LlmMessage(role: 'assistant', textContent: content));
          final outcome = await _dispatchAction(
            action,
            step,
            lastActionSig: lastActionSig,
            repeatedActions: repeatedActions,
          );
          if (outcome.done != null) return outcome.done!;
          lastResult = outcome.result;
          lastActionSig = outcome.sig;
          repeatedActions = outcome.repeats;
      }
```

- [ ] **Step 4: 删除 `_appendAssistantHistory` 方法**

In `lib/src/agent/phone_agent.dart`, 删除整个 `_appendAssistantHistory` 方法（含其 doc 注释，原 201–214 行附近）。它已被 Step 3 里的 `messages.add(LlmMessage(role: 'assistant', textContent: content))` 取代。

- [ ] **Step 5: 删除已失效的简写格式 PhoneAgent 测试**

In `test/phone_agent_test.dart`, 删除以下三个测试（简写格式已不再支持）：
- `test('parses Launch shorthand from model output', ...)`（约 330–346 行）
- `test('parses Tap shorthand with coordinates', ...)`（约 348–364 行）
- `test('parses screenshot shorthand as FinishAction', ...)`（约 366–374 行）

保留 `parses finish action from model output`（用的是 `finish(message=...)`，仍有效）。

- [ ] **Step 6: 跑 PhoneAgent 测试，确认通过**

Run: `dart test test/phone_agent_test.dart`
Expected: PASS。重点验证仍通过的用例：`returns failure when LLM output has no parseable action`（消息含 `Could not parse an action` 与 `Task complete`）、`retries once on a truncated (length) response`、`does not retry an unparseable response that was not truncated`、`strips <think> blocks from assistant history`（assistant 历史为去 think 的 content）。

- [ ] **Step 7: 分析 + 全量测试**

Run: `dart analyze --fatal-infos --fatal-warnings && dart test`
Expected: 无 error；全部测试 PASS。

- [ ] **Step 8: 提交**

```bash
git add scrcpy_mcp/lib/src/agent/phone_agent.dart scrcpy_mcp/test/phone_agent_test.dart
git commit -m "refactor(agent): consume ParsedResponse in PhoneAgent

Switch on ParsedAction/ParseFailure; drop the duplicated <think> regex
stripping, the empty/null special cases, and _appendAssistantHistory.
Remove obsolete shorthand-format agent tests."
```

---

## Task 3: 收尾 —— 合并类型、删除 `ActionParser`、改 barrel export

把 `PhoneAction` 类型迁入 `response_parser.dart`，删除 `action_parser.dart`，更新引用与导出，删除旧 `ActionParser` 单元测试组。

**Files:**
- Modify: `lib/src/agent/response_parser.dart`
- Delete: `lib/src/agent/action_parser.dart`
- Modify: `lib/src/tools/run_task.dart:6`
- Modify: `lib/scrcpy_mcp.dart:1`
- Modify: `test/phone_agent_test.dart`

- [ ] **Step 1: 把 `PhoneAction` 类型迁入 `response_parser.dart`**

In `lib/src/agent/response_parser.dart`, 把文件顶部这两行：

```dart
import 'action_parser.dart';

// PhoneAction 类型暂留在 action_parser.dart，Task 3 再迁入本文件。
export 'action_parser.dart' show PhoneAction, DoAction, FinishAction;
```

替换为（从 `action_parser.dart` 原样搬来的类型定义）：

```dart
/// Represents a single action the autoglm-phone model wants to execute.
sealed class PhoneAction {
  const PhoneAction();
}

final class DoAction extends PhoneAction {
  const DoAction({
    required this.action,
    this.element,
    this.start,
    this.end,
    this.text,
    this.app,
    this.duration,
    this.message,
  });

  final String action;
  final List<int>? element; // [x, y]
  final List<int>? start; // [x, y]
  final List<int>? end; // [x, y]
  final String? text;
  final String? app;
  final String? duration;
  final String? message;

  @override
  String toString() => 'DoAction($action)';
}

final class FinishAction extends PhoneAction {
  const FinishAction(this.message);
  final String message;

  @override
  String toString() => 'FinishAction($message)';
}
```

- [ ] **Step 2: 删除 `action_parser.dart`**

```bash
git rm scrcpy_mcp/lib/src/agent/action_parser.dart
```

- [ ] **Step 3: 更新 `run_task.dart` 的 import**

In `lib/src/tools/run_task.dart`, 把第 6 行：

```dart
import '../agent/action_parser.dart';
```

改为：

```dart
import '../agent/response_parser.dart';
```

- [ ] **Step 4: 更新 barrel export**

In `lib/scrcpy_mcp.dart`, 把第 1 行：

```dart
export 'src/agent/action_parser.dart';
```

改为：

```dart
export 'src/agent/response_parser.dart';
```

- [ ] **Step 5: 删除旧 `ActionParser` 单元测试组**

In `test/phone_agent_test.dart`, 删除整个 `group('ActionParser', () { ... });`（约 379–502 行，从注释 `// ── ActionParser unit tests ──` 到该 group 的结尾 `});`）。这些用例已被 `test/response_parser_test.dart` 覆盖。删除后，`phone_agent_test.dart` 不再直接引用解析器类，仅通过 `PhoneAgent` 行为测试。

- [ ] **Step 6: 分析 + 全量测试**

Run: `dart analyze --fatal-infos --fatal-warnings && dart test`
Expected: 无 error、无 warning（特别是不再有对 `action_parser.dart` / `ActionParser` 的悬空引用）；全部测试 PASS。

- [ ] **Step 7: 提交**

```bash
git add scrcpy_mcp/lib/src/agent/response_parser.dart scrcpy_mcp/lib/src/tools/run_task.dart scrcpy_mcp/lib/scrcpy_mcp.dart scrcpy_mcp/test/phone_agent_test.dart
git commit -m "refactor(agent): consolidate PhoneAction into response_parser, drop ActionParser

Move action types into response_parser.dart, delete action_parser.dart,
repoint imports + barrel export, remove the old ActionParser test group."
```

---

## 完成标准

- `ResponseParser.parse` 返回 sealed `ParsedResponse`（`ParsedAction` / `ParseFailure`，基类含 `think`/`content`）。
- `PhoneAgent` 不含任何 `<think>`/动作解析正则，仅对 `ParsedResponse` 做 `switch`。
- 仅支持 `do()` 与 `finish()`；简写格式、`screenshot()` 别名、未知函数兜底均已移除。
- 自由文本字段（text/message/app/instruction）容忍未转义引号。
- `action_parser.dart` 已删除，`ActionParser` 公开 API 由 `ResponseParser` 取代。
- `dart analyze --fatal-infos --fatal-warnings` 干净，`dart test` 全绿。
