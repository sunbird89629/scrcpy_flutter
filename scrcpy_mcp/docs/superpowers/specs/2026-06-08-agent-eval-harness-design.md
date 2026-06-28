# Agent Eval Harness 设计

日期：2026-06-08
范围：`scrcpy_mcp` 包的测试与评测工具层

## 背景

`scrcpy_mcp` 已经有 `run_task` / `PhoneAgent`，并且近期补了多项稳定性改进：
截断重试、截图历史裁剪、黑屏截图重试、跨步 memory、重复动作熔断、视觉断言 helper。
这些改动解决了部分真机失败模式，但当前缺少一套固定、可复跑的评测 harness 来回答：

- agent 改动后，固定任务完成率是否变好？
- 失败发生在哪一步，属于哪类失败？
- 最终结果是否真的到达目标界面，而不是只返回了成功文本？

下一步应先建立真机任务评测能力，再继续扩大 agent 能力。

## 目标

第一版提供一个轻量的 Agent Eval Harness：

- 用固定 case 批量驱动现有 `PhoneAgent` 在真机上执行任务。
- 每个 case 明确任务指令、前置 setup、最大步数和成功断言。
- 记录每次运行的步骤、动作、截图、最终结果和断言结果。
- 输出结构化产物，便于人工复盘和跨版本比较。
- 将失败归类为少量稳定枚举，方便统计趋势。

## 非目标

- 不进入正式 MCP API，不改变 `run_task` 的对外协议。
- 不改 `PhoneAgent` 的行为；harness 只做外围编排、记录和断言。
- 不做 dashboard、网页 UI 或复杂报表。
- 不引入 YAML/JSON case 解析；第一版用 Dart 代码定义 case。
- 不做自动修复或自动 prompt 调参。

## 推荐方案

采用“Dart case 定义 + 统一 runner + 结构化 artifact”的方案。

备选方案曾考虑：

1. 只扩展现有 E2E 测试：成本低，但失败报告分散，无法稳定比较不同版本。
2. 先做离线 trace 分析：适合 debug，但不能替代真机复跑。

推荐方案更贴合现状：已有 `PhoneAgent`、真实设备测试和视觉断言 helper，只缺统一编排和产物归档。

## 文件边界

新增测试/工具层文件：

```text
test/phone_agent_eval/
  agent_eval_case.dart
  agent_eval_runner.dart
  agent_eval_result.dart
  agent_eval_failure.dart
  agent_eval_test.dart

test/phone_agent_eval/cases/
  settings_navigation.dart
  twitter_home.dart
  youtube_history_recent.dart
```

运行产物写入：

```text
temp/agent_eval_runs/<timestamp>/<case-id>/
  result.json
  steps.jsonl
  final.txt
  screenshots/
```

`temp/` 已存在于仓库根目录，评测产物属于本地运行输出，不应提交到 git。

## 数据结构

### AgentEvalCase

Case 先用 Dart 代码定义，避免第一版引入配置解析，同时便于表达 setup 和跳过逻辑。

```dart
class AgentEvalCase {
  const AgentEvalCase({
    required this.id,
    required this.description,
    required this.task,
    required this.config,
    this.setup,
    required this.assertions,
  });

  final String id;
  final String description;
  final String task;
  final AgentConfig config;
  final Future<void> Function(AgentEvalDevice device)? setup;
  final List<AgentEvalAssertion> assertions;
}
```

`AgentEvalDevice` 是 runner 传给 setup 的窄接口，封装当前 device id、ADB 和常用动作。
它避免 case 直接依赖完整 runner 内部状态。

### Assertions

第一版支持两类断言：

```dart
sealed class AgentEvalAssertion {
  const AgentEvalAssertion();
}

final class TextContainsAssertion extends AgentEvalAssertion {
  const TextContainsAssertion(this.expected);
  final String expected;
}

final class VisualContainsAssertion extends AgentEvalAssertion {
  const VisualContainsAssertion(this.expectation);
  final String expectation;
}
```

`TextContainsAssertion` 检查 `AgentResult.result`。
`VisualContainsAssertion` 在最终屏幕截图上复用现有视觉断言 helper。

### AgentEvalResult

```dart
class AgentEvalResult {
  const AgentEvalResult({
    required this.caseId,
    required this.success,
    required this.failureKind,
    required this.finalResult,
    required this.steps,
    required this.duration,
    required this.assertions,
  });

  final String caseId;
  final bool success;
  final AgentEvalFailureKind? failureKind;
  final String finalResult;
  final int steps;
  final Duration duration;
  final List<AgentEvalAssertionResult> assertions;
}
```

`success` 只有在 agent 自身成功且全部断言通过时才为 `true`。
agent 返回成功但视觉断言失败，应归为失败。

### Failure Kind

```dart
enum AgentEvalFailureKind {
  parseFailure,
  maxSteps,
  stalled,
  repeatedAction,
  humanRequired,
  toolError,
  textAssertionFailed,
  visualAssertionFailed,
  unknown,
}
```

第一版不要求修改 `PhoneAgent` 返回结构。
失败分类从 `AgentResult.result` 的现有文本中识别：

| 文本特征 | 分类 |
| --- | --- |
| `Could not parse an action` | `parseFailure` |
| `Max steps` | `maxSteps` |
| `screen unchanged` / `unchanged` | `stalled` |
| `repeated the same action` | `repeatedAction` |
| `requires human` | `humanRequired` |
| setup 或 action runner 抛错 | `toolError` |
| 文本断言失败 | `textAssertionFailed` |
| 视觉断言失败 | `visualAssertionFailed` |
| 无法识别 | `unknown` |

后续如果需要更严谨，再把 `failureKind` 提升为 `AgentResult` 的结构化字段。

## 执行流程

`AgentEvalRunner.runCase(case)`：

1. 创建 case 专属产物目录：
   `temp/agent_eval_runs/<timestamp>/<case-id>/`
2. 执行 `case.setup`。
   setup 用于回桌面、启动目标 app、等待页面稳定或清理前置状态。
3. 构造 `PhoneAgent`。
   使用 case 的 `AgentConfig`，注入现有 `ChatFn`、截图 provider 和 `ActionRunner`。
4. 包装截图 provider。
   每次截图计算 hash；按配置保存 png 到 `screenshots/`；写入 `steps.jsonl`。
5. 包装 action runner。
   每次动作写入 action summary、原始 action 字符串和执行结果。
6. 可选包装 `ChatFn`。
   如果实现成本低，记录 LLM 文本和 finish reason；如果影响边界，第一版可以只记录 action 与结果。
7. 执行 `agent.run(case.task)`。
8. 对 agent 结果做失败分类。
9. 执行 case assertions。
   断言失败会覆盖最终 success，并设置对应 failure kind。
10. 写出 `result.json`、`final.txt`，并返回 `AgentEvalResult`。

## Artifact 格式

### steps.jsonl

每行一个事件。第一版支持这些类型：

```json
{"type":"screenshot","step":0,"hash":"...","path":"screenshots/000.png"}
{"type":"action","step":0,"summary":"Tap(500,300)","raw":"do(action=\"Tap\", element=[500,300])","result":"Tapped"}
{"type":"assertion","kind":"visual_contains","passed":true,"reason":"..."}
{"type":"final","success":true,"steps":4,"result":"done"}
```

如果包装 `ChatFn`，额外支持：

```json
{"type":"llm_response","step":0,"finishReason":"stop","text":"..."}
```

### result.json

包含单次 case 的总结果：

```json
{
  "caseId": "youtube_history_recent",
  "success": false,
  "failureKind": "maxSteps",
  "steps": 30,
  "durationMs": 123456,
  "finalResult": "Max steps (30) reached without completing the task.",
  "assertions": []
}
```

## 初始 Cases

第一版只放 3 个真机 case，避免评测本身变成大工程。

| Case | 目的 | 成功判断 |
| --- | --- | --- |
| `settings_navigation` | 验证基础导航、Launch/Back/视觉断言 | 最终界面包含 Android 设置页目标文本 |
| `twitter_home` | 验证打开应用和到达主页 | 视觉断言识别 Twitter/X 主页 |
| `youtube_history_recent` | 验证长列表任务的收敛能力 | 最终文本包含视频条目，且视觉断言确认处在 YouTube 历史相关界面 |

真机 case 不默认在 CI 运行。
通过环境变量启用：

```text
SCRCPY_RUN_AGENT_EVAL=1
```

缺少设备、模型环境变量或目标 app 前置条件时，测试应 skip，而不是失败。

## 错误处理

- setup 失败：记录 `toolError`，写出 result，不继续执行 agent。
- 截图失败：记录 `toolError`，写出 result。
- action runner 抛错：保持现有 `PhoneAgent` 行为，由 agent 接收错误结果并尝试恢复；runner 同时记录事件。
- agent 返回失败：按文本分类 failure kind。
- agent 返回成功但断言失败：最终 eval 失败，failure kind 使用断言失败类型。
- 视觉断言模型无法解析：作为 `visualAssertionFailed`，reason 保留原始异常文本。

## 测试策略

### 单元测试

无需真机和模型：

- failure kind 分类函数。
- `AgentEvalResult` JSON 序列化。
- `TextContainsAssertion` 成功/失败。
- fake screenshot/action runner 下，`AgentEvalRunner` 能写出 `result.json` 和 `steps.jsonl`。

### 真机评测测试

需要显式环境变量：

```text
SCRCPY_RUN_AGENT_EVAL=1
```

并依赖现有真机测试前置：

- 已连接 Android device。
- 模型 API 环境变量可用。
- 目标 app 已安装并登录。

真机评测应面向本地开发和回归比较，不作为默认 CI 阻断项。

## 后续扩展

第一版完成后，可以按实际痛点扩展：

- 把 `failureKind` 提升为 `AgentResult` 结构化字段。
- 增加 case 级 tags 和按 tag 运行。
- 增加 run summary，统计 N 个 case 的通过率和失败分布。
- 增加离线 trace 分析器。
- 将 case 从 Dart 迁移到 JSON/YAML，前提是 setup 需求稳定下来。

## 验收标准

- 能在本地通过 `dart test` 跑完 eval 单元测试。
- 设置环境变量后，能运行 3 个真机 eval case。
- 每个 case 都写出 `result.json`、`steps.jsonl` 和 `final.txt`。
- agent 成功但断言失败时，eval 结果必须失败。
- 失败结果能归类到明确 `AgentEvalFailureKind`，无法识别时为 `unknown`。
