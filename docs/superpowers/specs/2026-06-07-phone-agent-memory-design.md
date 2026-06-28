# PhoneAgent 跨步记忆 (<memory>) 设计

日期：2026-06-07
范围：`scrcpy_mcp/lib/src/agent/{agent_config,response_parser,phone_agent}.dart` 及对应测试

## 背景与动机

PhoneAgent 每步只看到当前截图（旧截图被 `keepScreenshots` 裁掉）。在滚动收集类任务（如「收集 YouTube 观看历史」）中，模型必须每轮把已看到的数据在推理里重新抄一遍——易漏、易超 token 窗。

借鉴 midscene 的 `<memory>` 机制（`ConversationHistory.memories`）：让模型有一个贯穿各步的"笔记本"，把关键信息显式记下来、自动回注到后续每轮的 prompt 中。midscene 调研见 [midscene-planning-comparison.md](../../scrcpy_mcp/docs/midscene-planning-comparison.md)。

## 第 1 节：提示词

在现有提示词的**动作定义之后、17 条规则之前**（即 `agent_config.dart` 原第 44 行 `finish(message="xxx")` 说明与 `必须遵循的规则：` 之间），插入独立节 `## 跨步记忆`：

```
## 跨步记忆

当你观察到当前截图中有**后续步骤需要用到的重要信息时**（如列表内容、联系人、
价格、日期等），用 `<memory>…</memory>` 标签记录下来。必须逐字照抄原始信息，
不得翻译、归纳、合并或简化。

每条信息单独记录；滚动、翻页后位置和序号可能变化，需要重新确认。

格式示例：
<memory>
视频1: "极客湾" - 19:27 - 1万次观看
视频2: "老范速评 6月3日" - 老范讲故事 - 1:45:35
</memory>

如果没有需要跨步保留的信息，不要输出 `<memory>` 标签。
```

关键约束：逐字照抄、每条单独记、滚动后重新确认、无信息不强制输出。

## 第 2 节：输出格式

新增 `<memory>` 标签，夹在 `<think>` 和 `<answer>` 之间，**可选**（不需要记时不出）：

```
<think>{推理}</think>
<memory>{记忆文本，可选}</memory>
<answer>do(action="Tap", ...)</answer>
```

## 第 3 节：解析（`ResponseParser`）

**`ParsedResponse` 基类**加 `final String memory`：

```dart
sealed class ParsedResponse {
  const ParsedResponse({
    required this.think,
    required this.content,
    required this.memory,
  });
  final String think;
  final String content;
  final String memory;  // NEW
}
```

`ParsedAction` / `ParseFailure` 的 `super.memory` 参数保持一致。

**`_split`**：在剥掉 `<think>` 之后、解 `<answer>` 之前，抠 `<memory>`。和现有 `<think>` 剥离逻辑对称：

```dart
static (String think, String content, String memory) _split(String text) {
  var think = '';
  final thinkMatch = RegExp(r'<think>(.*?)</think>', dotAll: true).firstMatch(text);
  if (thinkMatch != null) think = thinkMatch.group(1)!.trim();
  var content = text.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');
  // NEW: extract <memory>
  var memory = '';
  final memoryMatch = RegExp(r'<memory>(.*?)</memory>', dotAll: true).firstMatch(content);
  if (memoryMatch != null) {
    memory = memoryMatch.group(1)!.trim();
    content = content.replaceAll(RegExp(r'<memory>.*?</memory>', dotAll: true), '');
  }
  final answerMatch = RegExp(r'<answer>\s*(.*?)\s*</answer>', dotAll: true).firstMatch(content);
  if (answerMatch != null) content = answerMatch.group(1)!;
  return (think, content.trim(), memory);
}
```

`memory` 是纯字符串，不做二次解析。`_parseDo` 等逻辑不动——`<memory>` 已在 `_split` 从 `content` 里剔除，不影响后续匹配。

## 第 4 节：PhoneAgent —— 收集与回注

### 收集

`run()` 局部变量 `final memories = <String>[]`。每步 `ParsedAction`：
```dart
if (parsed.memory.isNotEmpty) memories.add(parsed.memory);
```

### 回注

`_buildUserContent` 里，当 `memories` 非空时，在反馈文字前面拼一块：

```dart
String _buildUserContent(int step, String message, String? lastResult,
    List<String> memories) =>
    step == 0
    ? message
    : '${memories.isEmpty ? '' :
        '跨步记录：\n---\n${memories.join('\n---\n')}\n---\n'
      }上一步操作结果：${lastResult ?? '已执行'}。请对照当前截图判断是否生效，并继续完成任务。';
```

`memories` 存在 `run()` 局部、不依赖 `messages` 列表——`_trimHistory` 截图像素不会影响它，与 midscene 独立存储等效。

## 第 5 节：测试

- **`ResponseParser`**：新增测试——`<memory>` 提取正确且 content 不受污染；无 `<memory>` 时 `memory == ''`；`<memory>` 含多行；`<think>` + `<memory>` + `<answer>` 全部出现时的 think/content/memory 正确分离。
- **`PhoneAgent`**：新测——`memories` 在回注文本中正确出现；多步累积；空 memory 不影响。
- 既有测试无回归。

## 第 6 节：非目标

- 不对 memory 文本做语义理解、结构化、或自动合并条目——就是存纯文本、原样回注。
- 不引入 `compressHistory` 条数压缩（独立改进，本次不做）。
- 模型何时用 memory、记什么内容——由提示词规则引导，代码不做判断。
