# PhoneAgent 跨步记忆 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 PhoneAgent 加跨步结构化记忆：AutoGLM 模型输出可选 `<memory>` 标签，解析后由 PhoneAgent 回注到后续每轮 user 消息。

**Architecture:** `<memory>` 夹在 `<think>` 和 `<answer>` 间独立标签；`ResponseParser._split` 抠取 + `ParsedResponse.memory` 字段；`PhoneAgent.run` 攒 `List<String> memories` 并通过 `_buildUserContent` 回注。提示词在 17 条规则前加 `## 跨步记忆` 节。

**Tech Stack:** Dart，`package:test`，melos 工作区。

参考 spec：`docs/superpowers/specs/2026-06-07-phone-agent-memory-design.md`

---

## Task 1: `ResponseParser` —— `<memory>` 提取 + `ParsedResponse.memory`

**Files:**
- Modify: `scrcpy_mcp/lib/src/agent/response_parser.dart`
- Test: `scrcpy_mcp/test/response_parser_test.dart`

**Work from:** `scrcpy_mcp`

- [ ] **Step 1: 写失败测试**

在 `test/response_parser_test.dart` 的 `group('ResponseParser', ...)` 末尾追加：

```dart
    test('extracts <memory> when present', () {
      final parsed = ResponseParser.parse(
        '<think>推理</think>'
        '<memory>视频1: "赛博参观极客湾" - 19:27</memory>\n'
        'do(action="Tap", element=[1, 2])',
      );
      expect(parsed.memory, '视频1: "赛博参观极客湾" - 19:27');
      expect(parsed, isA<ParsedAction>());
      final a = (parsed as ParsedAction).action;
      expect(a.action, 'Tap');
      expect(a.element, [1, 2]);
    });

    test('<memory> is optional / absent → memory is empty', () {
      final parsed = ResponseParser.parse('do(action="Back")');
      expect(parsed.memory, '');
      expect(parsed, isA<ParsedAction>());
    });

    test('<memory> multiline content preserved verbatim', () {
      final parsed = ResponseParser.parse(
        '<think>t</think>\n'
        '<memory>视频1: "A" - 1万\n视频2: "B" - 2万</memory>\n'
        'do(action="Tap", element=[1, 2])',
      );
      expect(parsed.memory, '视频1: "A" - 1万\n视频2: "B" - 2万');
    });

    test('<think> + <memory> + <answer> together', () {
      final parsed = ResponseParser.parse(
        '<think>推理</think>\n'
        '<memory>记东西</memory>\n'
        '<answer>do(action="Back")</answer>',
      );
      expect(parsed.think, '推理');
      expect(parsed.memory, '记东西');
      expect(parsed, isA<ParsedAction>());
    });
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `dart test test/response_parser_test.dart -N memory`
Expected: 4 个新测试 FAIL（`ParsedResponse` 没有 `memory` 字段；`_split` 不抠 `<memory>`）。

- [ ] **Step 3: 实现解析**

在 `lib/src/agent/response_parser.dart` 中：

(a) `ParsedResponse` 基类加 `memory`。把：

```dart
sealed class ParsedResponse {
  const ParsedResponse({required this.think, required this.content});
  final String think;
  final String content;
}
```

改为：

```dart
sealed class ParsedResponse {
  const ParsedResponse({
    required this.think,
    required this.content,
    required this.memory,
  });
  final String think;
  final String content;
  final String memory;
}
```

(b) `ParsedAction` 构造加 `super.memory`：

```dart
final class ParsedAction extends ParsedResponse {
  const ParsedAction({
    required super.think,
    required super.content,
    required super.memory,
    required this.action,
  });
  final PhoneAction action;
}
```

(c) `ParseFailure` 构造加 `super.memory`：

```dart
final class ParseFailure extends ParsedResponse {
  const ParseFailure({
    required super.think,
    required super.content,
    required super.memory,
    required this.reason,
  });
  final String reason;
}
```

(d) `_split` 返回 (think, content, memory) 三元组，并在剥 `<think>` 后抠 `<memory>`。把整个 `_split` 方法替换为：

```dart
  static (String think, String content, String memory) _split(String text) {
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

    var memory = '';
    final memoryMatch = RegExp(
      r'<memory>(.*?)</memory>',
      dotAll: true,
    ).firstMatch(content);
    if (memoryMatch != null) {
      memory = memoryMatch.group(1)!.trim();
      content = content.replaceAll(
        RegExp(r'<memory>.*?</memory>', dotAll: true),
        '',
      );
    }

    final answerMatch = RegExp(
      r'<answer>\s*(.*?)\s*</answer>',
      dotAll: true,
    ).firstMatch(content);
    if (answerMatch != null) content = answerMatch.group(1)!;

    return (think, content.trim(), memory);
  }
```

(e) `parse` 方法里解构 `_split` 和构造结果对象，全部加 `memory:`。也就是说做这些改动：

```dart
// parse() 开头：
    final (think, content, memory) = _split(text);   // 曾是 (think, content)
```

所有 `ParseFailure(` 和 `ParsedAction(` 构造（共 3 处 ParseFailure + 3 处 ParsedAction）都加 `memory: memory,` 参数。

具体位置：`parse()` 中 `ParseFailure(reason: 'empty/think-only response')`、`ParsedAction(...FinishAction...)`（finish 分支）、`ParseFailure(reason: 'malformed do()...')`、`ParsedAction(...DoAction...)`（do 分支）、`ParseFailure(reason: 'no action token')`。

- [ ] **Step 4: 跑解析器测试，确认通过**

Run: `dart test test/response_parser_test.dart`
Expected: PASS（既有 + 4 新 memory 测试）。

- [ ] **Step 5: 确认既有 PhoneAgent/全局测试无回归**

Run: `dart test test/phone_agent_test.dart`
Expected: PASS（PhoneAgent 还没开始调 memory，但 `ParsedResponse` 的构造签名变了，phone_agent 在 `_requestAction` 里创建 `ResponseParser.parse(...)` 结果时不传 memory 会编译失败——所以 Step 3 改完后马上改 phone_agent 的构造点，让它传 `memory: ''`。见 Task 2，但先在这里验证 rest 不崩）。

如果有编译错误（phone_agent 还在旧 `_split` 之类的引用），那就说明需要 Task 2 同步——那就直接将 Task 2 的改动合并到本 Step，一并提交。预期是可同步通过的（phone_agent 里没有直接调 `_split`，只有 `ResponseParser.parse`，结果类型构造签名变了但 phone_agent 不自己 new 它）。

- [ ] **Step 6: 分析**

Run: `dart analyze --fatal-infos --fatal-warnings`
Expected: No issues found。

- [ ] **Step 7: 提交**

```bash
git add scrcpy_mcp/lib/src/agent/response_parser.dart scrcpy_mcp/test/response_parser_test.dart
git commit -m "feat(agent): extract <memory> tag in ResponseParser

Add ParsedResponse.memory field; _split now returns (think, content, memory)
triplet, capturing an optional <memory> block between <think> and <answer>."
```

---

## Task 2: Prompt + PhoneAgent —— 收集/回注

**Files:**
- Modify: `scrcpy_mcp/lib/src/agent/agent_config.dart`
- Modify: `scrcpy_mcp/lib/src/agent/phone_agent.dart`
- Test: `scrcpy_mcp/test/phone_agent_test.dart`

**Work from:** `scrcpy_mcp`

- [ ] **Step 1: 写 PhoneAgent 失败测试**

在 `test/phone_agent_test.dart` 的 `group('PhoneAgent', ...)` 末尾追加：

```dart
    test('injects memory into user messages', () async {
      final capturingFake = _CapturingLlmClient([
        const LlmResponse(
          text:
              '<think>t</think><memory>视频1: A - 1万</memory>do(action="Tap", element=[1,2])',
        ),
        const LlmResponse(text: 'finish(message="done")'),
      ]);

      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        llmClient: capturingFake,
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );

      await agent.run('collect videos');

      // The second call's user message (step 1's feedback) should carry the memory.
      final secondCall = capturingFake.capturedMessages[1];
      final lastUser = secondCall.lastWhere((m) => m.role == 'user');
      expect(lastUser.textContent, contains('跨步记录'));
      expect(lastUser.textContent, contains('视频1: A - 1万'));
    });
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `dart test test/phone_agent_test.dart -N "injects memory"`
Expected: FAIL（PhoneAgent 不收集/回注 memory）。

- [ ] **Step 3: 写提示词**

在 `lib/src/agent/agent_config.dart` 中，`finish(message="xxx")` 说明行之后、`必须遵循的规则：` 之前（原来的第 44 行 `finish是结束任务的操作…` 之后），插入：

```dart
      ## 跨步记忆

      当你观察到当前截图中有**后续步骤需要用到的重要信息时**（如列表内容、联系人、价格、日期等），用 `<memory>…</memory>` 标签记录下来。必须逐字照抄原始信息，不得翻译、归纳、合并或简化。

      每条信息单独记录；滚动、翻页后位置和序号可能变化，需要重新确认。

      格式示例：
      <memory>
      视频1: "极客湾" - 19:27 - 1万次观看
      视频2: "老范速评 6月3日" - 老范讲故事 - 1:45:35
      </memory>

      如果没有需要跨步保留的信息，不要输出 `<memory>` 标签。

      '''
```

注意：提示词是 Dart 多行字符串（`'''…'''`）里的内容，`'''` 闭合要放在 memory 节之后，不要提前闭合。当前第 43-44 行（`finish(message="xxx")\n    finish是结束任务的操作…`）之后、第 46 行 `必须遵循的规则：` 之前插入。

- [ ] **Step 4: 改 PhoneAgent**

(a) `_buildUserContent` 签名加 `List<String> memories` 参数，并在 user 消息头部拼回注文本。把：

```dart
  String _buildUserContent(int step, String message, String? lastResult) =>
      step == 0
      ? message
      : '上一步操作结果：${lastResult ?? '已执行'}。请对照当前截图判断是否生效，并继续完成任务。';
```

改为：

```dart
  String _buildUserContent(int step, String message, String? lastResult,
      List<String> memories) {
    if (step == 0) return message;
    final memoryBlock = memories.isEmpty
        ? ''
        : '跨步记录：\n---\n${memories.join('\n---\n')}\n---\n';
    return '${memoryBlock}上一步操作结果：${lastResult ?? '已执行'}。请对照当前截图判断是否生效，并继续完成任务。';
  }
```

(b) `run()` 顶部（`final messages = _buildInitialMessages();` 后）加一行：

```dart
    final memories = <String>[];
```

(c) `run()` 里调用 `_buildUserContent` 的两处（step 0 和后续步，现在分别在第 49 行和第 71 行附近），都加上 `memories` 参数：

```dart
      final userContent = _buildUserContent(step, message, lastResult, memories);
```
（原来是 `_buildUserContent(step, message, lastResult)`。）

(d) `run()` 里 `ParsedAction(:final action, :final content)` 分支，在 `messages.add(...)` 之后、`_dispatchAction(...)` 之前加：

```dart
          if (parsed.memory.isNotEmpty) memories.add(parsed.memory);
```

（注意：`parsed` 已解构为 `(:final action, :final content)`，需改为同时解构 `memory`：`ParsedAction(:final action, :final content, :final memory)`。）

- [ ] **Step 5: 跑 PhoneAgent 测试**

Run: `dart test test/phone_agent_test.dart`
Expected: PASS（新增 memory 测试 + 既有测试）。

- [ ] **Step 6: 分析 + 全量单测**

Run: `dart analyze --fatal-infos --fatal-warnings && dart test test/response_parser_test.dart test/phone_agent_test.dart`
Expected: 无 error；全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add scrcpy_mcp/lib/src/agent/agent_config.dart scrcpy_mcp/lib/src/agent/phone_agent.dart scrcpy_mcp/test/phone_agent_test.dart
git commit -m "feat(agent): cross-step memory via <memory> tag

Add prompt rule for recording key screenshot info, collect memories in
PhoneAgent, and inject them back into each subsequent user message."
```

---

## 完成标准

- 模型输出 `<memory>…</memory>` 时，`ParsedResponse.memory` 正确提取；无标签时 `memory == ''`。
- `PhoneAgent` 逐步收集非空 memory，并通过 `_buildUserContent` 拼回后续每轮 user 消息头部。
- 提示词有 `## 跨步记忆` 节，位置正确（动作定义后、规则前）。
- `dart analyze` 干净，解析器 + agent 测试全绿。
