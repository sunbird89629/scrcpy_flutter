# Per-Model Client Architecture

**Date:** 2026-06-18
**Status:** Approved design
**Scope:** `scrcpy_mcp/lib/src/agent/`

## Context & Problem

The phone agent talks to multiple GUI models that differ in **system prompt** and
**output conventions**, but the current code expresses those differences
inconsistently:

- `AutoGLMClient` is a thin transport (HTTP only). Its prompt lives in
  `AgentConfig.systemPrompt` and its output is parsed by `ResponseParser` inside
  `PhoneAgent`.
- `AgentCPMGuiClient` is a fat adapter — it owns its own system prompt and
  translates its JSON output into `do(...)` text inside `chat`.

This session established that the **bigmodel-hosted `autoglm-phone`** and the
**open-source `AutoGLM-Phone-9B`** are two distinct targets that will coexist
long-term (see mem0 project memory, 2026-06-18):

- Official `autoglm-phone`: emits **inline prose reasoning + a bare `do(...)`
  line**; ignores the `<think>/<answer>/<memory>` wrappers the official
  Open-AutoGLM prompt mandates. No cross-step `<memory>`.
- Open-source `AutoGLM-Phone-9B` (arch = GLM-4.1V-9B-Thinking): honors the
  `<think>…</think><answer>…</answer>(+<memory>)` format.

The two share the **same OpenAI-compatible transport and the same `do(...)`
action grammar (coord space 0–999)**. Their only real differences are the
system prompt and whether `<memory>` cross-step memory exists.

## Goals

- Express **each model as its own client** — a self-contained adapter owning its
  prompt and behavior. This is the user's explicit architectural decision: model
  differences should be visible at the client boundary.
- Formalize the pattern `AgentCPMGuiClient` already follows into an interface.
- No transport duplication between the two AutoGLM clients.

## Non-Goals

- No change to `ResponseParser` — it is already tag-tolerant (strips
  `<think>/<memory>/<answer>` if present, regex-finds `do(` anywhere) and is
  shared by all three models.
- No model-specific `parse` on the interface yet (YAGNI — all three normalize to
  `do(...)` text today). Add only when open-source serving proves it necessary.
- No standing up open-source serving in this change; only the client + prompt.

## Architecture

### Contract: `AgentModelClient`

PhoneAgent depends on this interface instead of a bare `ChatFn` + a
config-owned prompt:

```dart
abstract interface class AgentModelClient {
  /// System prompt with {DATE}/{SCREEN_SIZE} placeholders; PhoneAgent
  /// substitutes runtime values before sending.
  String get systemPromptTemplate;

  /// Whether the model produces cross-step <memory> entries.
  bool get memoryEnabled;

  Future<LlmResponse> chat({required List<LlmMessage> messages});
}
```

Prompt **templating stays in PhoneAgent** (single source of date/screen-size
logic); the client only declares the template string.

### Shared transport: `OpenAiChatClient`

An abstract base holding the OpenAI-compatible POST (request body, sampling
params `temperature`/`top_p`/`frequency_penalty`/`max_tokens`, `finish_reason`
logging). Subclasses supply `baseUrl`/`apiKey`/`model`. Both AutoGLM clients
extend it → zero transport duplication.

### Concrete clients

| Client | prompt | `memoryEnabled` | transport |
|---|---|---|---|
| `AutoGLMOfficialClient` (rename of `AutoGLMClient`) | `kOfficialPrompt` | `false` | extends `OpenAiChatClient`, bigmodel endpoint |
| `AutoGLMOpenSourceClient` | `kOpenSourcePrompt` | `true` | extends `OpenAiChatClient`, self-hosted endpoint |
| `AgentCPMGuiClient` (retrofit) | existing `_systemPrompt` | `false` | own `chat` (different request/JSON format) |

- `fromEnv`/`fromTest`/`withClient` factories move from `AutoGLMClient` to
  `AutoGLMOfficialClient`.
- `AutoGLMOpenSourceClient` gets a `fromEnv` reading its own endpoint env vars.
- `AgentCPMGuiClient` retrofit: add `systemPromptTemplate` getter (returns its
  `_systemPrompt`; it has no `{DATE}/{SCREEN_SIZE}` placeholders, so substitution
  is a harmless no-op) and `memoryEnabled => false`; implement
  `AgentModelClient`. Its internal output translation stays in `chat`.

### Prompts: new file `agent_prompts.dart`

- `kOpenSourcePrompt` = the current `_kDefaultSystemPrompt` (with
  `<think>/<answer>/<memory>`), moved verbatim out of `agent_config.dart`.
- `kOfficialPrompt` = new, derived from the open-source prompt by:
  - **Removing** the format/wrapper instruction (current lines 5–11: the
    `<think>{think}</think>` / `<answer>{action}</answer>` block) and the
    `## 跨步记忆` / `<memory>` section (current lines 47–59).
  - **Keeping** the header (`{DATE}`, `{SCREEN_SIZE}`, role line), the full
    `do(...)` action list, the coordinate-space note (0–999), and the 17
    numbered rules.
  - **Replacing** the output instruction with a short directive: "先简要说明你的
    判断，然后另起一行输出且仅输出一个 `do(...)` 或 `finish(...)` 指令，不要输出任何
    标签或多余内容。"

## Data Flow (unchanged except the seam)

1. `PhoneAgent.run` → `_buildInitialMessages` substitutes `{DATE}/{SCREEN_SIZE}`
   into `client.systemPromptTemplate`.
2. `_requestAction` → `client.chat(messages)` → `ResponseParser.parse(text)`
   (shared). Truncation retry logic unchanged.
3. Assistant turn stored in history as **only the `do(...)` action line**
   (model-agnostic improvement; strips leaked prose for official, no-op for
   open-source whose `content` is already the action).
4. Memory append gated: `if (client.memoryEnabled && memory.isNotEmpty)`.

## Migration & Impact

- `AgentConfig`: remove the `systemPrompt` field; keep `maxSteps`,
  `keepScreenshots`, `stallThreshold`, `repeatedActionThreshold`, `screenSize`.
- `PhoneAgent`: constructor param `llmClient: ChatFn` → `client: AgentModelClient`.
- Construction sites to migrate: eval runner (`agent_eval_runner.dart` /
  `agent_eval_real_device_test.dart` currently pass `chat: AutoGLMClient.fromTest().chat`),
  MCP entry point, and any mock-client tests using `AutoGLMClient.withClient`.
  Default path uses `AutoGLMOfficialClient`.
- `ChatFn` typedef may remain for `DeepLocateActionRunner` (its second-pass
  refine call takes a `ChatFn`); `AgentModelClient.chat` matches that shape, so
  pass `client.chat`.

## Testing

- `ResponseParser` tests: unchanged.
- New: `kOfficialPrompt` contains no `<think>`/`<answer>`/`<memory>` tokens and
  retains all `do(...)` action names + the 17 rules.
- New: history stores only the `do(...)` line given a prose-prefixed reply.
- New: `memoryEnabled` gating — official client run does not accumulate memory.
- Migrate existing mock-client tests to `AutoGLMOfficialClient.withClient`.
- Real-device eval (`SCRCPY_RUN_AGENT_EVAL=1`) defaults to the official client.

## Resolved Decisions

- (a) Rename `AutoGLMClient` → `AutoGLMOfficialClient` (disambiguation over churn).
- (b) Prompts live in a new `agent_prompts.dart`.
