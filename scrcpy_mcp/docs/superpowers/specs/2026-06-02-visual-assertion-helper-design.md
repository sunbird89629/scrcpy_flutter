# 视觉断言 Helper 设计

日期：2026-06-02
范围：`scrcpy_mcp` 包的测试工具

## 背景与动机

`test/phone_agent_test/screenshot_content_test.dart` 中已有一段「截图 → 问 VLM
界面上是否出现 X → 返回是/否」的逻辑（私有的 `_askModel`）。这个模式被验证可行，
值得抽成可复用的**视觉断言原语**，供多个测试场景使用。

同时发现两个现存问题：

1. `screenshot_content_test.dart` 用 `response.contains('是')` 判定匹配，
   但模型回答「不是」时也包含「是」字 —— 存在误判 bug。
2. `phone_agent_test_real.dart` 的 e2e 测试结尾只有 `expect(agentResult, isNotNull)`，
   没有真正校验 agent 是否到达目标界面，等于没验证任务成败。

## 目标

提供一个通用、灵活的视觉断言工具，覆盖三类场景：

- e2e 任务的成功校验（agent 跑完后确认到达目标界面）
- 流程中的中间步骤断言（多步操作之间插检查点）
- 独立的界面内容检查（单独问「当前界面有没有 X」）

## 非目标

- 不引入对模型 structured/JSON output 能力的依赖（AutoGLM-phone 为输出动作微调，
  JSON 输出不稳）。
- 不把该工具放进 `lib/`（shipped 代码）；它是测试工具，留在 `test/`。
- 不做超出当前三场景的扩展。

## 设计决策（已与用户确认）

| 决策点 | 选择 |
| --- | --- |
| 用途 | 三场景全覆盖，做成通用原语 |
| 返回语义 | 返回结构体，调用方自己 `expect`（最灵活） |
| 输入面 | 纯函数核心 + 便捷封装层 |
| 解析策略 | 方案 A：严格格式提示 + 首词解析 |

## 架构

新增共享 helper 文件：`test/phone_agent_test/visual_assertion.dart`，
两个测试文件均 import 它。三层结构：

### 1. 数据结构

```dart
class ScreenCheckResult {
  const ScreenCheckResult({required this.matched, required this.reason});
  final bool matched;   // 模型判定是否匹配
  final String reason;  // 模型完整回答，断言失败时打印
}
```

### 2. 解析器（纯函数，可离线单测）

```dart
/// 纯字符串 → 结果，不依赖设备/模型。
ScreenCheckResult parseScreenCheckResponse(String raw);
```

规则：

- `trim()` 后取首行。
- 首行以「否」或「不」开头 → `matched: false`。
- 首行以「是」开头 → `matched: true`。
- 空串或其它无法判定的内容 → 抛 `LlmException`（不默默判 false）。
- `reason` 保留模型完整回答。

**注意先判「否/不」再判「是」**，以根除 `contains('是')` 误判。

### 3. 核心纯函数（问模型）

```dart
/// 给定截图，问模型 expectation 是否出现在界面上。
/// 无法解析时抛 LlmException。
Future<ScreenCheckResult> checkScreenContains({
  required LlmClient client,
  required String base64Screenshot,
  required String expectation,
  String mimeType = 'image/png',
});
```

系统提示词强制格式：**第一行只写「是」或「否」，第二行起写理由**。
内部组装 `LlmMessage`（system + 带图 user），调用 `client.chat`，
将 `response.text` 交给 `parseScreenCheckResponse`。

### 4. 便捷封装（设备感知层）

```dart
/// 自动截图后再调 checkScreenContains。
Future<ScreenCheckResult> checkDeviceScreenContains({
  required LlmClient client,
  required ScrcpyMcpAdb adb,
  required String deviceId,
  required String expectation,
});
```

内部 `adb.takeScreenshot(deviceId)` → `base64Encode` → `checkScreenContains`。

## 数据流

```
调用方
  └─(便捷层) checkDeviceScreenContains
       └─ adb.takeScreenshot → base64
            └─(核心) checkScreenContains
                 └─ client.chat(system + 带图 user)
                      └─ parseScreenCheckResponse(text) → ScreenCheckResult
                           └─ 调用方 expect(r.matched, isTrue, reason: r.reason)
```

## 各场景调用方式

```dart
// 独立检查 / 中间步骤：
final r = await checkDeviceScreenContains(
  client: client, adb: adb, deviceId: _deviceId, expectation: '应用图标');
expect(r.matched, isTrue, reason: r.reason);

// e2e 成功校验（agent.run 之后）：
final r = await checkDeviceScreenContains(
  client: AutoglmLlmClient.fromTest(), adb: adb, deviceId: _deviceId,
  expectation: 'Twitter（X）的主页');
expect(r.matched, isTrue, reason: r.reason);
```

## 错误处理

- 模型回答无法解析（空 / 非「是否不」开头）→ `parseScreenCheckResponse` 抛
  `LlmException`，测试以异常失败，而非静默误判。
- 截图 / 网络 / 模型 API 错误沿用现有 `AdbClient` 与 `AutoglmLlmClient` 的异常。

## 测试策略

- **单元测试**（无需真机/模型，CI 可跑）：新增 `visual_assertion_test.dart`，
  用样例字符串覆盖 `parseScreenCheckResponse`：
  - `是` / `是\n因为...` → matched true
  - `否` / `不是` / `不\n...` → matched false
  - 空串 / 纯空白 → 抛异常
  - 乱码（如 `这个界面看起来像...`）→ 抛异常
  - 首尾含空白 / 多行 → 正确取首行
- **集成测试**（需真机 + 模型）：重构后的 `screenshot_content_test.dart` 与
  `phone_agent_test_real.dart`。

## 配套改动

1. 新增 `test/phone_agent_test/visual_assertion.dart`。
2. 新增 `test/phone_agent_test/visual_assertion_test.dart`（纯解析单测）。
3. 重构 `screenshot_content_test.dart` 改用 helper，移除私有 `_askModel`，
   修正 `contains('是')` 误判。
4. 在 `phone_agent_test_real.dart` 的 `agent.run()` 之后加入真实成功校验。

## 工作量

小：1 个 helper 文件 + 1 个纯解析单测 + 改 2 个现有测试文件。
