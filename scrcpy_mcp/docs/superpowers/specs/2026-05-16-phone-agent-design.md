# Phone Agent for scrcpy_mcp — Design Spec

**Date:** 2026-05-16  
**Status:** Approved

## Overview

Add a `run_task` MCP tool to `scrcpy_mcp` that accepts a natural-language instruction and executes it autonomously on an Android device using a ReAct agent loop driven by an OpenAI-compatible LLM. The agent reuses all existing scrcpy MCP tools (screenshot, touch, key injection, etc.) as its action space.

## Architecture

New files under `scrcpy_mcp/lib/src/agent/`:

```
scrcpy_mcp/lib/src/
├── agent/
│   ├── agent_config.dart          # max_steps, system_prompt, model, base_url, api_key
│   ├── llm_client.dart            # Abstract LlmClient + LlmResponse + ToolCall types
│   ├── openai_llm_client.dart     # HTTP implementation (OpenAI-compatible)
│   └── phone_agent.dart           # ReAct loop
└── tools/
    └── run_task.dart              # New MCP tool wrapping PhoneAgent.run()
```

`ScrcpyMcpServer` gains an optional `PhoneAgent? agent` constructor parameter. When present, `run_task` is registered alongside existing tools. When absent (the default), server behaviour is unchanged — no breaking changes.

`bin/scrcpy_mcp.dart` reads environment variables at startup to decide whether to construct a `PhoneAgent`:

```
OPENAI_BASE_URL   e.g. https://api.openai.com/v1
OPENAI_API_KEY    sk-...
OPENAI_MODEL      e.g. gpt-4o
SCRCPY_AGENT_MAX_STEPS   default 15
```

If `OPENAI_API_KEY` is absent, no agent is constructed and `run_task` is not registered.

## PhoneAgent — ReAct Loop

```
PhoneAgent.run(message) → AgentResult
  │
  ├─ Build messages: [system_prompt, user: message]
  │
  └─ loop (step < max_steps):
       │
       ├─ LlmClient.chat(messages, tools=scrcpy tool schemas)
       │     ↓
       │   LlmResponse
       │     ├─ finish_reason == stop      → return success (LLM text as result)
       │     ├─ finish_reason == tool_calls
       │     │     → execute each tool call via McpTool.execute()
       │     │     → append assistant + tool messages
       │     │     → continue loop
       │     └─ error / unparseable        → throw LlmException
       │
       └─ step == max_steps → return failure (steps exhausted)
```

**Tool schemas** are generated from existing `McpTool.inputSchema` instances — no duplication. The agent's available tools are always in sync with what the MCP server advertises.

**Return type:**

```dart
class AgentResult {
  final String result;
  final int steps;
  final bool success;
}
```

## LlmClient Abstraction

```dart
abstract class LlmClient {
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required List<ToolSchema> tools,
  });
}
```

`OpenAiLlmClient` implements this using `package:http`, posting to `$baseUrl/chat/completions`. Compatible with OpenAI, DeepSeek, Qwen, and any OpenAI-format endpoint.

`LlmClient` is an interface so unit tests can provide a `FakeLlmClient` without network calls.

## System Prompt

```
你是一个 Android 设备控制助手，通过 scrcpy 协议操控手机。

规则：
1. 每步先截图了解当前界面，再决定下一步操作
2. 任务完成后直接用自然语言回复结果，不要再调用工具
3. 遇到无法完成的情况，说明原因后停止
4. 坐标使用截图返回的实际分辨率（width × height）
```

Rule 4 addresses a known coordinate-space mismatch: the LLM must use the resolution
reported by `take_screenshot` (device pixels) rather than estimating from a
visually-scaled rendering.

## Error Handling

| Situation | Behaviour |
|-----------|-----------|
| HTTP 4xx/5xx from LLM | Throw `LlmException`; `run_task` returns `success: false` |
| Tool execution failure | Append error as tool result; let LLM attempt recovery |
| Steps exhausted | Return `success: false` with final step count |
| Unparseable LLM output | Throw `LlmException`; `run_task` catches and returns `success: false` |

Tool failures do **not** abort the loop — the error is fed back to the LLM as an
observation so it can try a different approach.

## run_task MCP Tool

```
Input:
  device_id  string  (required — device serial to operate on)
  message    string  Natural language task

Output:
  result     string  LLM's final answer or failure description
  steps      int     Number of steps executed
  success    bool
```

`run_task` calls `start_mirroring(device_id)` automatically before entering the
agent loop so that session-based tools (`inject_touch`, `inject_key`, etc.) are
available. It does **not** stop mirroring afterwards — the caller decides when to
clean up.

## Testing

| Layer | Approach |
|-------|----------|
| `PhoneAgent` unit | Mock `LlmClient` + mock `McpTool`; verify normal completion, steps-exhausted, tool-failure recovery |
| `OpenAiLlmClient` unit | Mock `http.Client`; verify request format and response parsing |
| `RunTaskTool` unit | Mock `PhoneAgent`; verify MCP result format |
| Real device | `test/real_device_agent_test.dart` — requires connected device + env vars |

## Non-Goals

- Async task queue (can be added later if needed)
- Multi-device parallelism
- Conversation history across multiple `run_task` calls (each call is stateless)
