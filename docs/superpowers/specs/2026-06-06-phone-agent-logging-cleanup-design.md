# PhoneAgent 日志清理设计

日期：2026-06-06
范围：`scrcpy_mcp/lib/src/agent/phone_agent.dart`、`packages/adb_tools/lib/src/adb_process_runner.dart` 及对应测试

## 背景与动机

当前 agent 运行日志「太乱」，主要噪音来源（来自实跑样本）：

1. **重复**：`_requestAction` 先 `_log.fine('rawText:<全文>')`，紧接着 `MessageList.add` 又 `_log.fine('assistant:<全文>')`——同一段模型回复几乎打两遍。
2. **user 反馈行**：`MessageList.add` 把每条 user 消息（`上一步操作结果：…`）也打出来，与结果信息重复。
3. **ADB 装饰块**：`AdbProcessRunner._formatResult` 输出 5 行 `>>>>>` 框，且 `result:$r` = `Instance of 'ProcessResult'`（无意义）。

目标（用户确认）：

- **结构化两档**：默认 INFO 给「每步一行」的可扫读索引；完整推理 + ADB 明细在 FINE。
- **全文推理单份保留**：模型推理是调 agent 行为的主要依据，必须**全文、不截断、只打一份**。
- **去重 + 去噪**：消除 rawText/assistant 双打、user 行噪音、ADB 装饰块。

## 分级与每步形态

| 级别 | 内容 |
|------|------|
| **INFO** | `task: <任务>`（运行开始一次）；`step N  <动作摘要>`（动作索引行）；`step N → <结果>` |
| **FINE** | `reply:` + 全文推理（含 `do(...)`，单份不截断）；ADB 一行 |

一步的目标样子：

```
[INFO] PhoneAgent  step4  Wait(2s)
[FINE] PhoneAgent  reply:
  看起来页面正在加载，显示"历史记录"标题，但页面内容还在加载中。
  我应该等待页面加载。由于已有2秒内置延迟，我需要再等待一段时间。
  do(action="Wait", duration="2 seconds")
[FINE] adb_tools.AdbProcessRunner: adb -s 11081FDD4004DY shell input tap 969 2197 → exit 0
[INFO] PhoneAgent  step4 → Waited 2s
```

去重效果：reply 由原来 2 份（rawText + assistant）降为 1 份；user 反馈行不再单独打（结果已在 INFO `→` 行）；系统提示词不再被打印。

## PhoneAgent 改造（`phone_agent.dart`）

1. **删除 `MessageList` 类**。它继承 `DelegatingList` 仅为在 `add` 时打日志（`_log.fine(value.toLog())`）——这是重复的根源。`run()` 内的 `messages` 改回普通 `List<LlmMessage>`（`<LlmMessage>[]`）。`_buildInitialMessages` 返回 `List<LlmMessage>`，`_requestAction`/`_trimHistory` 形参相应改为 `List<LlmMessage>`。
2. **删除 `_requestAction` 中两处** `_log.fine('rawText:...')` / `_log.fine('rawText(retry):...')`。保留 `_log.info('output truncated (length); retrying with a concise nudge')`（截断重试信号）。
3. **`run()` 起始**：`_log.info('task: $message')` 打一次任务。
4. **`run()` 内对 `ParsedResponse` 分支显式打日志**：
   - `ParsedAction(:final action, :final content)`：
     - `_log.info('step $step  ${_actionSummary(action)}')`（索引行）
     - `_log.fine('reply:\n${_indentBlock(content)}')`（全文推理单份；`content` 已去 `<think>` 标签，对 autoglm 即完整回复）
     - 分发后打结果行：`final resultText = outcome.done?.result ?? outcome.result ?? '(no result)'; _log.info('step $step → $resultText');`（DoAction 走 `outcome.result`；FinishAction/最大步等终止情形走 `outcome.done!.result`），随后保持原有 `if (outcome.done != null) return outcome.done!;` 等控制流
   - `ParseFailure(:final reason, :final content)`：
     - `_log.warning('step $step parse failed: $reason')`
     - `_log.fine('reply(unparsed):\n${_indentBlock(content)}')`（便于排查）
     - 返回失败 `AgentResult`（逻辑不变）
5. **新增助手** `_actionSummary(PhoneAction)`：紧凑渲染动作，例：
   - `Tap(897,939)` / `Long Press(x,y)` / `Double Tap(x,y)`
   - `Swipe(499,702→499,263)`
   - `Type("张三")` / `Type_Name("李四")`（文本超过 ~20 字截断加 `…`）
   - `Launch(Chrome)` / `Wait(2s)` / `Back` / `Home`
   - `Note` / `Call_API` / `Interact` / `Take_over`（无坐标动作仅名字）
   - `Finish("…")`（其文本截断）
6. **新增助手** `_indentBlock(String)`：把多行文本每行前加两空格缩进，使 FINE 的 `reply:` 块与表头对齐。

`_dispatchAction`、`_actionSignature`、`_trimHistory`（已接收 `List<LlmMessage>`，无需改）、`_buildUserContent`、`_stallAbort`、stall/repeat 逻辑均不变。

## AdbProcessRunner 改造（`adb_process_runner.dart`，共享包）

`_formatResult` 的 5 行 `>>>>>` 框改为一行。为可单测，把它从私有 `_formatResult` 改名为**包内可见**（非下划线）静态方法 `formatResultLine`（仍在 `src/`，不经 barrel 对外导出，等同包内私有，但允许同包测试直接调用）：

```dart
static String formatResultLine(String command, ProcessResult r) {
  final stderr = (r.stderr as Object?)?.toString().trim() ?? '';
  return stderr.isEmpty
      ? '$command → exit ${r.exitCode}'
      : '$command → exit ${r.exitCode} | stderr: $stderr';
}
```

`run()` 内 `_log.fine(_formatResult(...))` 改为 `_log.fine(formatResultLine([executable, ...arguments].join(' '), result))`。

- 仍在 FINE。命令**保留完整** `adb -s <serial> shell ...` 前缀（通用、安全，不裁剪）。
- 该包被多项目共用，但 `>>>>>` 框对所有使用者都是噪音，改为一行是普惠改进。

## 测试

- `adb_tools`：新增单测（`packages/adb_tools/test/`，`import 'package:adb_tools/src/adb_process_runner.dart';`）覆盖 `AdbProcessRunnerImpl.formatResultLine`——exit 0 无 stderr 时输出 `<cmd> → exit 0`；有 stderr 时追加 `| stderr: …`；并断言输出**不含** `>>>>` / `Instance of`。用 `ProcessResult(pid, exitCode, stdout, stderr)` 构造入参。
- `phone_agent`：现有行为测试不应回归。补充：
  - `_actionSummary` 对各动作的渲染（Tap/Swipe/Wait/Launch/Type/Back 等）。
  - 删除 `MessageList` 后 `run()` 仍正确累积历史、`_trimHistory` 仍生效（现有「keeps only the last keepScreenshots screenshots」等测试覆盖；确认 `messages` 类型切换不破坏断言）。
  - 现有「strips `<think>` blocks from assistant history」断言的是 assistant 历史内容 = `content`，不受日志改动影响（历史写入逻辑不变）。

## 非目标（评估后认为不需要改）

- **不改 `logger_utils`**：本次噪音全在调用点；其 `[时间] 级别 名字: 消息` 格式无需改动，reply 缩进由调用点拼字符串实现。它是多项目共用的 git 依赖，无实质收益不动。
- **不改 `mcp_tool.dart`**：它打的是 MCP 工具边界（`run_task ← args` / `→ Nms | summary`），刚好括住整次运行，有用且与本次噪音无关。
- **不改日志级别默认值**：debug=FINE / release=INFO 两档已契合需求（debug 下全文推理可见）。`hierarchicalLoggingEnabled` 已开，将来若要"看推理但静音 ADB"，给 `adb_tools.AdbProcessRunner` 单独设级别即可，无需改代码。
- 不改动 agent 的控制流、动作分发、stall/repeat 阈值、解析逻辑。
