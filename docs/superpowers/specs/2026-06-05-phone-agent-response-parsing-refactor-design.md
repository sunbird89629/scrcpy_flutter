# PhoneAgent 响应解析重构设计

日期：2026-06-05
范围：`scrcpy_mcp/lib/src/agent/{phone_agent,action_parser}.dart` 及对应测试

## 背景与动机

`PhoneAgent` 负责 autoglm-phone 的 ReAct 循环，但「响应解析」职责散落在两处：

- `ActionParser.parse()` 负责文本 → `PhoneAction`，返回 `PhoneAction?`，`null` 同时表示「没动作」和「格式坏了」，丢失原因。
- `PhoneAgent` 自己也掺解析细节：`_requestAction`（解析 + 截断重试）、`_appendAssistantHistory`（正则剥 `<think>`）、`run()` 的 null 分支（**再次**正则剥 `<think>` 拼错误信息）、空响应特判。

同一个「think / answer / content 分离」概念被切成两半，`<think>` 正则剥离重复两处。

本次重构目标（用户确认）：

1. **职责分离** —— 解析逻辑全部从 `PhoneAgent` 抽出，`PhoneAgent` 只管循环编排，不碰正则/文本细节。
2. **结构化解析结果** —— 解析返回带 `think` 的完整结果，消除 think 被两处正则重复剥离、结果信息丢失。
3. **健壮性/容错** —— 借鉴 midscene，自由文本字段用 `indexOf` 提取，容忍未转义引号等畸形输入。

附带收益：解析逻辑可脱离 LLM/循环单独测试。

设计取舍（用户确认）：

- 失败用**带原因的 sealed 结果类型**，而非异常或裸 `null`。
- 格式集**精简到实际需要**：提示词只教 `do(...)` 和 `finish(...)`，简写格式属过度设计，删除。

## 结果类型

`PhoneAction` / `DoAction` / `FinishAction` 保持不变。新增 sealed `ParsedResponse`，把 `think` 提升为一等字段：

```dart
sealed class ParsedResponse {
  const ParsedResponse({required this.think, required this.content});
  final String think;    // <think></think> 内的推理，无则 ''
  final String content;  // 其余全文：未标签推理 + 动作 token；喂给 history 的就是它
}

final class ParsedAction extends ParsedResponse {   // 成功
  const ParsedAction({required super.think, required super.content, required this.action});
  final PhoneAction action;
}

final class ParseFailure extends ParsedResponse {   // 失败，带原因
  const ParseFailure({required super.think, required super.content, required this.reason});
  final String reason;   // 如 "empty response" / "no action token" / "malformed do(): <细节>"
}
```

只两个变体。不细分 `NoAction` vs `Malformed`，因为 `PhoneAgent` 对两者处理一致（都失败、截断则重试），`reason` 字符串足以区分用于日志/错误信息（YAGNI）。

`think` 与 `content` 在解析阶段就分好，`PhoneAgent` 不再碰 `<think>` 正则。`content` 即「原文去掉 `<think></think>` 标签块」，保留未标签推理（模型常在此记录待总结的数据），正是当前 history 想存的内容。

## 解析器

`ActionParser` → 重命名 `ResponseParser`，`parse(String text) → ParsedResponse`，两段式：

```
parse(text):
  1. _split(text) → (think, content)     // 剥 <think>；若有 <answer> 取其内容；其余为 content
  2. content 去空白后为空  → ParseFailure(reason: "empty/think-only response")
  3. 识别 finish(...)       → ParsedAction(FinishAction)
     识别 do(...)           → 解析参数 → ParsedAction(DoAction) 或 ParseFailure("malformed do(): ...")
  4. 无任何动作 token       → ParseFailure(reason: "no action token")
```

**保留**（实际需要 + 容错）：

- `finish(message="...")` —— 贪婪匹配到最后的 `")`，容忍未转义内层引号（已有真实痛点，见现有测试 `finish() tolerates unescaped inner quotes`）。
- `do(action="...", ...)`：
  - 坐标类字段 `element` / `start` / `end` —— 数字正则提取（安全）。
  - 自由文本字段 `text` / `message` / `app` / `instruction` —— 改用 `indexOf` 提取到末尾 `")`（借鉴 midscene `extractValueAfter`），容忍未转义引号，如 `do(action="Type", text="他说"你好"")`。这是健壮性净增。
- `<answer>` 标签包裹、动作前的自然语言前缀。

**删除**（提示词从未要求、过度设计）：

- 简写格式 `Tap([...])` / `Launch("...")` / `Back()` / `Swipe(...)` / `Type_Name("...")`，及整个 `_parseShorthand` / `_mapShorthand` / `_splitArgs`。
- 未知函数名兜底分支。
- `screenshot()` 作为 finish 别名（提示词只有 `finish`）。

## PhoneAgent 改造

`run()` 循环第 2–3 步改为对 `ParsedResponse` 做 `switch`：

```dart
final parsed = await _requestAction(messages, userContent: ..., screenshot: ...);
switch (parsed) {
  case ParseFailure(:final reason, :final content):
    return AgentResult(
      result: 'Could not parse an action ($reason): $content',
      steps: step + 1, success: false,
    );
  case ParsedAction(:final action, :final content):
    messages.add(LlmMessage(role: 'assistant', textContent: content));
    final outcome = await _dispatchAction(action, step, ...);
    if (outcome.done != null) return outcome.done!;
    lastResult = outcome.result;
    lastActionSig = outcome.sig;
    repeatedActions = outcome.repeats;
}
```

**净删除**：

- `_appendAssistantHistory` 整个方法（含 `<think>` 正则）→ 直接 `add(content)`。
- `run()` 中 `rawText.isEmpty` 特判 → 归入 `ParseFailure("empty response")`。
- null-action 分支里第二次 `<think>` 正则剥离。

**`_requestAction` 改造**：返回类型 `({String rawText, PhoneAction? action})` → `ParsedResponse`。截断重试判据改为 `parsed is ParseFailure && response.finishReason == 'length'`，仍在 `_requestAction` 内（属 LLM 交互，非解析）。`_log.fine('rawText:...')` 保留，从 `response.text` 取原始全文。

结果：`PhoneAgent` 不含任何正则、不猜 `null` 含义；`_dispatchAction` / stall / repeat / trimHistory 等逻辑不变。

## 文件与命名

- `action_parser.dart` → `response_parser.dart`。
- `ActionParser` → `ResponseParser`。
- `PhoneAction` / `DoAction` / `FinishAction` + 新增 `ParsedResponse` / `ParsedAction` / `ParseFailure` 同放此文件。
- 更新引用：`phone_agent.dart` 的 import；`scrcpy_mcp.dart` barrel export（公开 API 名变更）。

## 测试调整

`test/phone_agent_test.dart`：

- **删**：所有简写相关测试（`parses Launch shorthand`、`parses Tap shorthand`、`Back/Swipe shorthand`、`Type_Name shorthand`、`parses screenshot shorthand`），PhoneAgent 组与 ActionParser 组中均有。
- **改**：`ActionParser` 测试组 → `ResponseParser`，断言对象 `PhoneAction?` → `ParsedResponse`（`isA<ParsedAction>()` 后取 `.action`）。
- **加**：
  - think / content 分离正确。
  - `ParseFailure` 各 reason（空响应、纯 think、无动作 token、malformed do()）。
  - `do(action="Type", text=...)` 含未转义引号正确提取。
- **保**：`do()` 关键字解析、未转义引号的 finish、Interact、Note、Call_API、敏感 `Tap`+message、截断重试、stall/repeat、max-steps、runner 抛异常恢复等行为测试（不受影响，仅可能因 API 改名微调）。

## 非目标

- 不改动 `_dispatchAction` 的动作分发逻辑（Take_over/Interact 需人工、repeat backstop 等）。
- 不改 `_trimHistory`、stall/repeat 阈值、截断重试的触发条件本身（仅迁移判据写法）。
- 不改 `LlmClient` 接口、不动 `agent_config.dart`。
- 不引入新的动作类型或坐标换算（坐标归一化换算是另一独立 TODO）。
