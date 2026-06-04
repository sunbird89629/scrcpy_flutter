# scrcpy_mcp 日志治理设计

- 日期：2026-06-04
- 范围：仅 `scrcpy_mcp` 包（`scrcpy_app` / `scrcpy_flutter` / `scrcpy_plus` / `scrcpy_view` / `packages/*` 本轮不动）

## 背景

`scrcpy_mcp` 全包仅约 31 处日志调用，量不大，问题在于**调用端约定不一致**。底层基建（`logger_utils` 的 console/file sink、按日轮转、`LoggerTrace` 扩展）写得不错，不需要改动。

现状问题：

1. **Logger 命名四种风格混用**：`scrcpy_mcp`（bin，snake）、`scrcpy.mcp`（mcp_tool，dot）、`scrcpy.mcp.llm`（dot 分层）、`scrcpy.recording`（dot 但漏了 mcp 层）、`PhoneAgent`（CamelCase）。
2. **Logger 变量名不统一**：`_log` / `_baseLogger` / `moduleLogger` 混用。
3. **`moduleLogger` 是死代码**：`bin/scrcpy_mcp.dart:9` 定义后全项目无人调用。
4. **级别使用不当**：完整 LLM `rawText`、每条消息 `toLog()` 都打在 `info`，release 模式（INFO 级）下会淹没审计主线。

## 设计决策

`logging` 包 root level 在 debug 模式为 `FINE`、release 模式为 `INFO`。治理目标是让这条分界线真正生效：**release 日志干净、debug 细节齐全**。

### ① Logger 命名 —— 统一 `scrcpy.mcp.*` 分层 dot 命名

| 文件 | 现在 | 改为 |
|---|---|---|
| `bin/scrcpy_mcp.dart` | `Logger('scrcpy_mcp')`（死代码） | **删除** |
| `lib/src/mcp_tool.dart` | `Logger('scrcpy.mcp')` | `Logger('scrcpy.mcp.tool')` |
| `lib/src/recording_controller.dart` | `Logger('scrcpy.recording')` | `Logger('scrcpy.mcp.recording')` |
| `lib/src/agent/autoglm_llm_client.dart` | `Logger('scrcpy.mcp.llm')` | 不变 |
| `lib/src/agent/phone_agent.dart` | `Logger('PhoneAgent')` | `Logger('scrcpy.mcp.agent')` |

`mcp_tool` 改名后，`lib/src/tools/` 下所有子类经 `McpTool.logger` getter 自动继承 `scrcpy.mcp.tool`，无需逐文件修改。分层命名同时让 `logging` 包能按前缀过滤（如只看 `scrcpy.mcp.agent`）。

### ② Logger 变量名 —— 统一 `_log`

- `mcp_tool.dart`：`_baseLogger` → `_log`，`logger` getter 保留为 `Logger get logger => _log;`
- `bin/scrcpy_mcp.dart`：删除 `moduleLogger`
- `recording_controller` / `autoglm_llm_client` / `phone_agent`：已是 `_log`，不变

### ③ 级别 —— 一行式审计留 INFO、整段转储降 FINE

| 位置 | 现在 | 改为 | 理由 |
|---|---|---|---|
| `phone_agent.dart:108` `rawText:$rawText` | info | **fine** | 每个 step 一大段 LLM 输出，调试细节 |
| `phone_agent.dart:125` `rawText(retry):$rawText` | info | **fine** | 同上 |
| `phone_agent.dart:268` `MessageList.add` 的 `value.toLog()` | info | **fine** | 每条消息整段转储，调试细节 |
| `phone_agent.dart:115` 截断重试提示 | info | **保留 info** | 稀疏关键信号 |
| `mcp_tool.dart:33` 入口 `$name ← $args` | info | **保留 info**，args 经 `McpTool.truncate(args.toString(), 200)` 截断 | 工具调用审计是 MCP server 日志的核心价值；截断保证审计行恒为一行 |
| `mcp_tool.dart:39/41` 工具结果摘要 | info/warning | 不变 | 已用 `truncate`，是审计主线 |

保留的级别语义：FINE=调试细节 / INFO=关键事件与工具审计 / WARNING=可恢复异常。

## 验证

1. 先排查测试是否断言了具体日志级别或内容（重点 `test/phone_agent_test.dart`、`test/run_task_tool_test.dart`），若有则同步调整。
2. `melos run analyze`（`--fatal-infos --fatal-warnings`）须通过。
3. `melos run test` 须全绿。

## 非目标（YAGNI）

- 不引入新的日志级别或封装层。
- 不修改 `logger_utils` 基建。
- 不治理其他模块，也不改根 `CLAUDE.md` 里"用 appLogger"那条（与本包无关，留待全 monorepo 统一时处理）。
