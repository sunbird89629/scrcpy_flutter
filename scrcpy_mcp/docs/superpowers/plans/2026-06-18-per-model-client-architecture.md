# Per-Model Client Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Express each GUI model as its own self-contained client behind an `AgentModelClient` interface, splitting `AutoGLMClient` into official + open-source variants over a shared transport base.

**Architecture:** A new `AgentModelClient` interface (systemPromptTemplate + memoryEnabled + chat) is the only thing `PhoneAgent` depends on. Two AutoGLM clients extend a shared `OpenAiChatClient` transport base; `AgentCPMGuiClient` is retrofitted to the interface. Prompts move to `agent_prompts.dart`. `ResponseParser` stays shared and untouched.

**Tech Stack:** Dart, `package:http` (+ `MockClient` from `package:http/testing.dart`), `package:test`, `package:meta` (`@visibleForTesting`).

## Global Constraints

- Logging: per-file `final _log = Logger('dotted.name')` from `package:logger_utils`; never `print`/`debugPrint`.
- Never add `test` as a dev_dependency (conflicts with `flutter_test`); `package:test` is already available in `scrcpy_mcp`.
- `ResponseParser` MUST NOT change — it is shared by all three clients.
- Action grammar (`do(...)`, coord space 0–999) is identical across all AutoGLM models.
- Run tests with `dart test <path>` from `scrcpy_mcp/`.
- Coordinate space and the 17 numbered rules MUST be preserved verbatim in both prompts.

---

## File Structure

- Create `lib/src/agent/agent_prompts.dart` — `kOfficialPrompt`, `kOpenSourcePrompt`.
- Create `lib/src/agent/agent_model_client.dart` — `AgentModelClient` interface.
- Create `lib/src/agent/openai_chat_client.dart` — `OpenAiChatClient` abstract transport base.
- Rename/rewrite `lib/src/agent/auto_glm_client.dart` — `AutoGLMOfficialClient` + `AutoGLMOpenSourceClient`.
- Modify `lib/src/agent/agentcpm_client.dart` — implement `AgentModelClient`.
- Modify `lib/src/agent/agent_config.dart` — remove `systemPrompt` field.
- Modify `lib/src/agent/phone_agent.dart` — depend on `AgentModelClient`; action-line history.
- Modify `lib/src/tools/run_task.dart`, `lib/src/mcp_http_server.dart` — pass a client.
- Create `test/utils/fake_model_client.dart` — `FakeModelClient` test double.
- Modify test call sites (enumerated in Task 4).

---

## Task 1: Prompts file

**Files:**
- Create: `lib/src/agent/agent_prompts.dart`
- Modify: `lib/src/agent/agent_config.dart` (move prompt out, reference new constant)
- Test: `test/agent_prompts_test.dart`

**Interfaces:**
- Produces: `const String kOpenSourcePrompt` (current `_kDefaultSystemPrompt` verbatim), `const String kOfficialPrompt`.

- [ ] **Step 1: Write the failing test**

```dart
// test/agent_prompts_test.dart
import 'package:scrcpy_mcp/src/agent/agent_prompts.dart';
import 'package:test/test.dart';

void main() {
  group('kOfficialPrompt', () {
    test('contains no think/answer/memory tags', () {
      for (final token in ['<think>', '<answer>', '<memory>']) {
        expect(kOfficialPrompt.contains(token), isFalse, reason: token);
      }
    });
    test('keeps the do() action vocabulary and coordinate space', () {
      for (final a in ['do(action="Launch"', 'do(action="Tap"',
          'do(action="Swipe"', 'finish(message=', '(999,999)']) {
        expect(kOfficialPrompt.contains(a), isTrue, reason: a);
      }
    });
    test('retains the numbered rules and runtime placeholders', () {
      expect(kOfficialPrompt.contains('{DATE}'), isTrue);
      expect(kOfficialPrompt.contains('{SCREEN_SIZE}'), isTrue);
      expect(kOfficialPrompt.contains('17.'), isTrue);
    });
  });

  group('kOpenSourcePrompt', () {
    test('keeps the think/answer/memory format', () {
      for (final token in ['<think>', '<answer>', '<memory>']) {
        expect(kOpenSourcePrompt.contains(token), isTrue, reason: token);
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/agent_prompts_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../agent_prompts.dart'`.

- [ ] **Step 3: Create `agent_prompts.dart`**

Move the entire current `_kDefaultSystemPrompt` string literal out of `agent_config.dart` into this file as `kOpenSourcePrompt`, then add `kOfficialPrompt` derived from it. Concretely:

```dart
// lib/src/agent/agent_prompts.dart

/// Open-source AutoGLM-Phone-9B prompt — the official Open-AutoGLM format with
/// <think>/<answer>/<memory> wrappers. Verbatim copy of the former
/// AgentConfig default prompt.
const String kOpenSourcePrompt = '''
今天的日期是: {DATE}
设备屏幕: {SCREEN_SIZE}px，坐标空间 [0,1000]
... (PASTE the existing _kDefaultSystemPrompt body verbatim, including the
<think>{think}</think>/<answer>{action}</answer> block, the do() list, the
## 跨步记忆 / <memory> section, and all 17 numbered rules) ...
''';

/// bigmodel-hosted autoglm-phone prompt — same task/action grammar, but WITHOUT
/// the <think>/<answer>/<memory> wrappers, which the hosted model ignores.
const String kOfficialPrompt = '''
今天的日期是: {DATE}
设备屏幕: {SCREEN_SIZE}px，坐标空间 [0,1000]
你是一个智能体分析专家，可以根据操作历史和当前状态图执行一系列操作来完成任务。
先简要说明你的判断，然后另起一行输出且仅输出一个操作指令（do(...) 或 finish(...)），不要输出任何 XML 标签或多余内容。

操作指令及其作用如下：
... (PASTE the do() action list lines verbatim from the existing prompt:
Launch, Tap, Tap+message, Type, Type_Name, Interact, Swipe, Note, Call_API,
Long Press, Double Tap, Take_over, Back, Home, Wait, finish) ...

必须遵循的规则：
... (PASTE rules 1–17 verbatim from the existing prompt) ...
''';
```

Build derivation rules for `kOfficialPrompt` (do NOT free-write the action/rule text — copy from the existing prompt):
- Drop the original format block `你必须严格按照要求输出以下格式：` + `<think>{think}</think>` + `<answer>{action}</answer>` + the `其中：{think}…{action}…` lines.
- Drop the entire `## 跨步记忆` section (the `<memory>` instructions and example).
- Keep header (date/screen lines), the full do() action list, and rules 1–17 exactly.

- [ ] **Step 4: Point `agent_config.dart` at the moved constant**

In `lib/src/agent/agent_config.dart`: delete the `_kDefaultSystemPrompt` literal, add `import 'agent_prompts.dart';`, and change the field default to keep current behavior for now:

```dart
// in AgentConfig constructor
this.systemPrompt = kOpenSourcePrompt,
```

- [ ] **Step 5: Run tests**

Run: `dart test test/agent_prompts_test.dart`
Expected: PASS (3 + 1 tests).
Run: `dart analyze lib/src/agent/agent_prompts.dart lib/src/agent/agent_config.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/src/agent/agent_prompts.dart lib/src/agent/agent_config.dart test/agent_prompts_test.dart
git commit -m "refactor(agent): extract prompts to agent_prompts.dart; add kOfficialPrompt"
```

---

## Task 2: `AgentModelClient` interface + `OpenAiChatClient` transport base

**Files:**
- Create: `lib/src/agent/agent_model_client.dart`
- Create: `lib/src/agent/openai_chat_client.dart`
- Test: `test/openai_chat_client_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class AgentModelClient { String get systemPromptTemplate; bool get memoryEnabled; Future<LlmResponse> chat({required List<LlmMessage> messages}); }`
  - `abstract class OpenAiChatClient implements AgentModelClient` with ctor `OpenAiChatClient({required String baseUrl, required String apiKey, required String model})` and `@visibleForTesting OpenAiChatClient.withHttp({required baseUrl, apiKey, model, required http.Client httpClient})`. Provides `chat(...)`. Leaves `systemPromptTemplate`/`memoryEnabled` abstract.

- [ ] **Step 1: Write the failing test**

```dart
// test/openai_chat_client_test.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrcpy_mcp/src/agent/agent_model_client.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:scrcpy_mcp/src/agent/openai_chat_client.dart';
import 'package:test/test.dart';

class _TestClient extends OpenAiChatClient {
  _TestClient(http.Client c)
      : super.withHttp(
          baseUrl: 'https://x/api', apiKey: 'k', model: 'm', httpClient: c);
  @override
  String get systemPromptTemplate => 'PROMPT';
  @override
  bool get memoryEnabled => false;
}

void main() {
  test('chat posts OpenAI body and parses content + finish_reason', () async {
    late http.Request seen;
    final mock = MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({
          'choices': [
            {'finish_reason': 'stop', 'message': {'content': 'do(action="Back")'}}
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = _TestClient(mock);
    final res = await client.chat(
      messages: const [LlmMessage(role: 'user', textContent: 'hi')],
    );
    expect(res.text, 'do(action="Back")');
    expect(res.finishReason, 'stop');
    expect(seen.url.toString(), 'https://x/api/chat/completions');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['model'], 'm');
    expect((body['messages'] as List).first['content'], 'hi');
  });

  test('implements AgentModelClient', () {
    expect(_TestClient(MockClient((_) async => http.Response('', 200))),
        isA<AgentModelClient>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/openai_chat_client_test.dart`
Expected: FAIL — URIs for `agent_model_client.dart` / `openai_chat_client.dart` don't exist.

- [ ] **Step 3: Create the interface**

```dart
// lib/src/agent/agent_model_client.dart
import 'llm_client.dart';

/// A self-contained adapter for one GUI model: owns its system prompt and
/// transport so model differences live at the client boundary. PhoneAgent
/// depends only on this interface.
abstract interface class AgentModelClient {
  /// System prompt with {DATE}/{SCREEN_SIZE} placeholders; PhoneAgent
  /// substitutes runtime values before sending.
  String get systemPromptTemplate;

  /// Whether the model emits cross-step <memory> entries.
  bool get memoryEnabled;

  Future<LlmResponse> chat({required List<LlmMessage> messages});
}
```

- [ ] **Step 4: Create the transport base**

Move the transport/`_messageToJson` logic out of the current `auto_glm_client.dart` (lines ~49–120) into this base. Preserve the sampling params and the `finish_reason != stop` warning.

```dart
// lib/src/agent/openai_chat_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger_utils/logger_utils.dart';
import 'package:meta/meta.dart';

import 'agent_model_client.dart';
import 'llm_client.dart';

final _log = Logger('scrcpy.mcp.llm');

/// Shared OpenAI-compatible transport for AutoGLM-family clients. Subclasses
/// supply endpoint/credentials and the prompt/memory policy.
abstract class OpenAiChatClient implements AgentModelClient {
  OpenAiChatClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  }) : _http = http.Client();

  @visibleForTesting
  OpenAiChatClient.withHttp({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required http.Client httpClient,
  }) : _http = httpClient;

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _http;

  @override
  Future<LlmResponse> chat({required List<LlmMessage> messages}) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': messages.map(_messageToJson).toList(),
      'max_tokens': 2048,
      'frequency_penalty': 0.5,
      'temperature': 0.3,
      'top_p': 0.7,
    });

    final response = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );
    if (response.statusCode != 200) {
      throw LlmException('HTTP ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choice = (json['choices'] as List).first as Map<String, dynamic>;
    final finishReason = choice['finish_reason'] as String?;
    if (finishReason != null && finishReason != 'stop') {
      _log.warning(
        '$model finish_reason="$finishReason" — output may be truncated or '
        'filtered; raise max_tokens or shorten the prompt.',
      );
    }
    final message = choice['message'] as Map<String, dynamic>;
    return LlmResponse(
      text: message['content'] as String?,
      finishReason: finishReason,
    );
  }

  Map<String, dynamic> _messageToJson(LlmMessage m) {
    final map = <String, dynamic>{'role': m.role};
    if (m.imageBase64 != null) {
      final parts = <Map<String, dynamic>>[];
      if (m.textContent != null) {
        parts.add({'type': 'text', 'text': m.textContent});
      }
      parts.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${m.imageMimeType};base64,${m.imageBase64}'},
      });
      map['content'] = parts;
    } else if (m.textContent != null) {
      map['content'] = m.textContent;
    }
    return map;
  }
}
```

- [ ] **Step 5: Run tests**

Run: `dart test test/openai_chat_client_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/agent/agent_model_client.dart lib/src/agent/openai_chat_client.dart test/openai_chat_client_test.dart
git commit -m "feat(agent): add AgentModelClient interface + OpenAiChatClient base"
```

---

## Task 3: Split into `AutoGLMOfficialClient` + `AutoGLMOpenSourceClient`; retrofit AgentCPM

**Files:**
- Rewrite: `lib/src/agent/auto_glm_client.dart`
- Modify: `lib/src/agent/agentcpm_client.dart`
- Modify (rename references): `test/auto_glm_client_test.dart`, `test/real_device_agent_test.dart:37`, `test/phone_agent_eval/agent_eval_real_device_test.dart:44`, `test/phone_agent_eval/youtube_tab_test.dart:105`, `test/phone_agent_eval/coordinate_calibration_test.dart:79`, `test/phone_agent_test/metadata_test.dart:51`, `test/phone_agent_test/phone_agent_test_real.dart:44`, `test/phone_agent_test/screenshot_content_test.dart:19,39`, `test/phone_agent_test/utils/adb_agent_runner.dart:28`, `test/phone_agent_test/youtube_history_test.dart:58`
- Test: `test/auto_glm_client_test.dart` (rewritten)

**Interfaces:**
- Consumes: `OpenAiChatClient` (Task 2), `kOfficialPrompt`/`kOpenSourcePrompt` (Task 1).
- Produces:
  - `class AutoGLMOfficialClient extends OpenAiChatClient` with `AutoGLMOfficialClient({required baseUrl, apiKey, model})`, `@visibleForTesting AutoGLMOfficialClient.withClient({...httpClient})`, `factory AutoGLMOfficialClient.fromEnv()`, `factory AutoGLMOfficialClient.fromTest()`; `systemPromptTemplate => kOfficialPrompt`; `memoryEnabled => false`.
  - `class AutoGLMOpenSourceClient extends OpenAiChatClient` with `AutoGLMOpenSourceClient({required baseUrl, apiKey, model})`, `@visibleForTesting .withClient`, `factory AutoGLMOpenSourceClient.fromEnv()`; `systemPromptTemplate => kOpenSourcePrompt`; `memoryEnabled => true`.
  - `AgentCPMGuiClient implements AgentModelClient` with `systemPromptTemplate` (its `_systemPrompt`) and `memoryEnabled => false`.

- [ ] **Step 1: Rewrite `auto_glm_client.dart`**

```dart
// lib/src/agent/auto_glm_client.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'agent_prompts.dart';
import 'openai_chat_client.dart';

/// bigmodel-hosted autoglm-phone. Emits inline prose + bare do(); no <memory>.
class AutoGLMOfficialClient extends OpenAiChatClient {
  AutoGLMOfficialClient({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
  });

  @visibleForTesting
  AutoGLMOfficialClient.withClient({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required http.Client httpClient,
  }) : super.withHttp(httpClient: httpClient);

  factory AutoGLMOfficialClient.fromEnv() => AutoGLMOfficialClient(
        baseUrl: Platform.environment['AUTOGLM_BASE_URL']!,
        apiKey: Platform.environment['AUTOGLM_API_KEY']!,
        model: Platform.environment['AUTOGLM_MODEL']!,
      );

  factory AutoGLMOfficialClient.fromTest() => AutoGLMOfficialClient(
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        apiKey: 'dc45fcec2e1743f1ae732cf3b6e6ad17.tMejaXqUvJbJ5zZO',
        model: 'autoglm-phone',
      );

  @override
  String get systemPromptTemplate => kOfficialPrompt;
  @override
  bool get memoryEnabled => false;
}

/// Self-hosted open-source AutoGLM-Phone-9B. Uses the <think>/<answer>/<memory>
/// format and supports cross-step memory.
class AutoGLMOpenSourceClient extends OpenAiChatClient {
  AutoGLMOpenSourceClient({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
  });

  @visibleForTesting
  AutoGLMOpenSourceClient.withClient({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required http.Client httpClient,
  }) : super.withHttp(httpClient: httpClient);

  factory AutoGLMOpenSourceClient.fromEnv() => AutoGLMOpenSourceClient(
        baseUrl: Platform.environment['AUTOGLM_OSS_BASE_URL']!,
        apiKey: Platform.environment['AUTOGLM_OSS_API_KEY'] ?? 'EMPTY',
        model: Platform.environment['AUTOGLM_OSS_MODEL']!,
      );

  @override
  String get systemPromptTemplate => kOpenSourcePrompt;
  @override
  bool get memoryEnabled => true;
}
```

- [ ] **Step 2: Retrofit `AgentCPMGuiClient`**

In `lib/src/agent/agentcpm_client.dart`: add `import 'agent_model_client.dart';`, change the class declaration to `class AgentCPMGuiClient implements AgentModelClient {`, and add these members (its `_systemPrompt` has no placeholders, so substitution is a harmless no-op):

```dart
  @override
  String get systemPromptTemplate => _systemPrompt;
  @override
  bool get memoryEnabled => false;
```

Its existing `chat({required List<LlmMessage> messages})` already matches the interface — add `@override` above it.

- [ ] **Step 3: Rewrite `auto_glm_client_test.dart` for the renamed class**

```dart
// test/auto_glm_client_test.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrcpy_mcp/src/agent/auto_glm_client.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:test/test.dart';

void main() {
  AutoGLMOfficialClient makeClient(http.Client mockHttp) =>
      AutoGLMOfficialClient.withClient(
        baseUrl: 'https://x/api', apiKey: 'k', model: 'autoglm-phone',
        httpClient: mockHttp,
      );

  test('official client returns parsed content and profile flags', () async {
    final client = makeClient(MockClient((_) async => http.Response(
          jsonEncode({
            'choices': [
              {'finish_reason': 'stop', 'message': {'content': 'do(action="Home")'}}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        )));
    final res = await client.chat(
      messages: const [LlmMessage(role: 'user', textContent: 'x')],
    );
    expect(res.text, 'do(action="Home")');
    expect(client.memoryEnabled, isFalse);
    expect(client.systemPromptTemplate.contains('<think>'), isFalse);
  });

  test('open-source client carries the tag prompt and memory flag', () {
    final client = AutoGLMOpenSourceClient.withClient(
      baseUrl: 'https://x/api', apiKey: 'k', model: 'AutoGLM-Phone-9B',
      httpClient: MockClient((_) async => http.Response('', 200)),
    );
    expect(client.memoryEnabled, isTrue);
    expect(client.systemPromptTemplate.contains('<answer>'), isTrue);
  });
}
```

- [ ] **Step 4: Rename all production references**

`AutoGLMClient` is referenced only via `.fromTest()`/`.fromEnv()` in tests (see Files list). Apply this uniform rename in each listed test file: replace `AutoGLMClient.fromTest()` → `AutoGLMOfficialClient.fromTest()` and `AutoGLMClient.fromEnv()` → `AutoGLMOfficialClient.fromEnv()`. Update the import in each file from `auto_glm_client.dart` if it referenced the old symbol by name (the file path is unchanged). NOTE: sites where the result is passed to `PhoneAgent`/`RunTaskTool` as `llmClient:`/`chat:` are further migrated in Task 4 — for now keep the `.chat` tear-off so the build stays green (e.g. `AutoGLMOfficialClient.fromTest().chat`).

- [ ] **Step 5: Run tests**

Run: `dart test test/auto_glm_client_test.dart test/openai_chat_client_test.dart`
Expected: PASS.
Run: `dart analyze lib/src/agent/auto_glm_client.dart lib/src/agent/agentcpm_client.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/src/agent/auto_glm_client.dart lib/src/agent/agentcpm_client.dart test/
git commit -m "feat(agent): split AutoGLMClient into Official/OpenSource clients; AgentCPM implements AgentModelClient"
```

---

## Task 4: Switch PhoneAgent/AgentConfig to `AgentModelClient`; migrate call sites

**Files:**
- Modify: `lib/src/agent/phone_agent.dart` (constructor, `_buildInitialMessages`, memory gate)
- Modify: `lib/src/agent/agent_config.dart` (remove `systemPrompt` field)
- Modify: `lib/src/tools/run_task.dart`, `lib/src/mcp_http_server.dart`
- Create: `test/utils/fake_model_client.dart`
- Modify (call sites): `test/phone_agent_test.dart` (makeAgent + per-test `llmClient:`), `test/phone_agent_eval/agent_eval_runner.dart:141`, `test/phone_agent_test/youtube_history_test.dart:56`, `test/phone_agent_test/utils/adb_agent_runner.dart:26`, `test/real_device_agent_test.dart`, `test/run_task_tool_test.dart`, `test/phone_agent_test/utils/visual_assertion.dart`

**Interfaces:**
- Consumes: `AgentModelClient` (Task 2), `AutoGLMOfficialClient` (Task 3).
- Produces: `PhoneAgent({required AgentConfig config, required AgentModelClient client, required ScreenshotProvider takeScreenshot, required ActionRunner actionRunner})`; `class FakeModelClient implements AgentModelClient` with ctor `FakeModelClient(ChatFn chat, {String systemPromptTemplate = 'SYS', bool memoryEnabled = false})`.

- [ ] **Step 1: Create the test double**

```dart
// test/utils/fake_model_client.dart
import 'package:scrcpy_mcp/src/agent/agent_model_client.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';

/// Wraps a [ChatFn] as an [AgentModelClient] for PhoneAgent tests.
class FakeModelClient implements AgentModelClient {
  FakeModelClient(this._chat,
      {this.systemPromptTemplate = 'SYS', this.memoryEnabled = false});

  final ChatFn _chat;
  @override
  final String systemPromptTemplate;
  @override
  final bool memoryEnabled;

  @override
  Future<LlmResponse> chat({required List<LlmMessage> messages}) =>
      _chat(messages: messages);
}
```

- [ ] **Step 2: Write the failing test (PhoneAgent uses client prompt + memory gate)**

Add to `test/phone_agent_test.dart` (it already has `_capturingChat`/`_fakeScreenshot`). First migrate `makeAgent` to the client (shown in Step 4), then add:

```dart
    test('uses the client systemPromptTemplate as the system message', () async {
      final captured = <List<LlmMessage>>[];
      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 1),
        client: FakeModelClient(
          _capturingChat([const LlmResponse(text: 'finish(message="done")')],
              captured),
          systemPromptTemplate: 'HELLO {SCREEN_SIZE}',
        ),
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );
      await agent.run('task');
      expect(captured.first.first.role, 'system');
      expect(captured.first.first.textContent, startsWith('HELLO '));
    });
```

- [ ] **Step 3: Run test to verify it fails**

Run: `dart test test/phone_agent_test.dart -n 'uses the client systemPromptTemplate'`
Expected: FAIL to compile — `PhoneAgent` has no `client` param.

- [ ] **Step 4: Change `PhoneAgent` + `AgentConfig`**

In `lib/src/agent/agent_config.dart`: remove the `systemPrompt` field and its constructor entry and the `agent_prompts.dart` import if now unused. (`screenSize` stays.)

In `lib/src/agent/phone_agent.dart`:
- Add `import 'agent_model_client.dart';`.
- Constructor: replace `required this.llmClient,` with `required this.client,`; replace field `final ChatFn llmClient;` with `final AgentModelClient client;`.
- In `_buildInitialMessages`, replace `config.systemPrompt` with `client.systemPromptTemplate`:

```dart
    var systemPrompt =
        client.systemPromptTemplate.replaceFirst('{DATE}', dateStr);
```

- In `_requestAction`, replace both `llmClient(messages: ...)` calls with `client.chat(messages: ...)`.
- Gate the memory append. Find `if (memory.isNotEmpty) memories.add(memory);` and change to:

```dart
          if (client.memoryEnabled && memory.isNotEmpty) memories.add(memory);
```

- [ ] **Step 5: Migrate `run_task.dart` and `mcp_http_server.dart`**

In `lib/src/tools/run_task.dart`: change the field/param `ChatFn llmClient` / `_llmClient` to `AgentModelClient client` / `_client` (update the 3 references: constructor param line 15, init line 20, field line 26), add `import '../agent/agent_model_client.dart';`, and in the `PhoneAgent(...)` call (line 73) pass `client: _client,` instead of `llmClient: _llmClient,`.

In `lib/src/mcp_http_server.dart`: change `ChatFn? llmClient` (line 20) to `AgentModelClient? llmClient` keeping the name, update the import, and pass it through unchanged at line 28 (`RunTaskTool` now takes `client:` — rename the named arg there to `client: llmClient`). If a default is constructed when null, use `AutoGLMOfficialClient.fromEnv()`.

- [ ] **Step 6: Migrate test call sites (uniform transformations)**

Apply these exact transformations:

1. `test/phone_agent_test.dart` `makeAgent`: replace `llmClient: _fakeChat(responses),` with `client: FakeModelClient(_fakeChat(responses)),` and add `import 'utils/fake_model_client.dart';`.
2. In the same file, each per-test `llmClient: chatFn,` / `llmClient: _fakeChat(...)` becomes `client: FakeModelClient(chatFn),` / `client: FakeModelClient(_fakeChat(...)),` (sites at lines 99, 130, 184, 215, 267, 336).
3. `test/phone_agent_eval/agent_eval_runner.dart:141` and `test/phone_agent_test/utils/adb_agent_runner.dart:26`: these build `PhoneAgent` from a `ChatFn chat` parameter — change the surrounding helper to accept `AgentModelClient client` and pass `client: client`. Their callers pass `AutoGLMOfficialClient.fromTest()` (was `...fromTest().chat`); drop the `.chat`.
4. `test/phone_agent_test/youtube_history_test.dart:56` `llmClient: AutoGLMOfficialClient.fromTest().chat,` → `client: AutoGLMOfficialClient.fromTest(),`.
5. `test/run_task_tool_test.dart` and `test/real_device_agent_test.dart`: wherever `RunTaskTool(... llmClient: X ...)` / agent wiring passes a `ChatFn`, pass an `AgentModelClient` (`AutoGLMOfficialClient.fromTest()` for real, or `FakeModelClient(fake)` for unit). Update `import`s.
6. `test/phone_agent_test/utils/visual_assertion.dart`: the `required ChatFn chat` params that forward into `PhoneAgent` become `required AgentModelClient client`; forward as `client: client`.

- [ ] **Step 7: Run the full suite**

Run: `dart test`
Expected: PASS for all non-`real-device` tests (real-device tests skip without `SCRCPY_RUN_AGENT_EVAL=1` / a device).
Run: `dart analyze lib test`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add lib test
git commit -m "refactor(agent): PhoneAgent depends on AgentModelClient; remove AgentConfig.systemPrompt"
```

---

## Task 5: Store only the `do(...)` action line in history

**Files:**
- Modify: `lib/src/agent/phone_agent.dart`
- Test: `test/phone_agent_test.dart`

**Interfaces:**
- Consumes: `PhoneAgent` (Task 4), `FakeModelClient` (Task 4).

- [ ] **Step 1: Write the failing test**

```dart
    test('stores only the do() action line in history, stripping prose',
        () async {
      final captured = <List<LlmMessage>>[];
      final agent = PhoneAgent(
        config: const AgentConfig(maxSteps: 2),
        client: FakeModelClient(_capturingChat([
          const LlmResponse(
              text: '好的，我需要点击。\ndo(action="Tap", element=[100,200])'),
          const LlmResponse(text: 'finish(message="done")'),
        ], captured)),
        takeScreenshot: _fakeScreenshot,
        actionRunner: (_) async => 'ok',
      );
      await agent.run('task');
      // Second call's history contains the prior assistant turn.
      final assistantTurns = captured[1]
          .where((m) => m.role == 'assistant')
          .map((m) => m.textContent)
          .toList();
      expect(assistantTurns, ['do(action="Tap", element=[100,200])']);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/phone_agent_test.dart -n 'stores only the do'`
Expected: FAIL — stored text includes the prose prefix `好的，我需要点击。`.

- [ ] **Step 3: Implement the action-line extractor**

In `lib/src/agent/phone_agent.dart`, add a private helper and use it where the assistant turn is recorded (current line 103, `messages.add(LlmMessage(role: 'assistant', textContent: content));`):

```dart
  /// Keep only the executable action call in history — strips any prose the
  /// model (e.g. hosted autoglm-phone) emits before the do()/finish() call.
  static String _actionLine(String content) {
    final m = RegExp(r'(do\(|finish\()').firstMatch(content);
    return m == null ? content.trim() : content.substring(m.start).trim();
  }
```

Change the record line to:

```dart
          messages.add(
            LlmMessage(role: 'assistant', textContent: _actionLine(content)),
          );
```

- [ ] **Step 4: Run tests**

Run: `dart test test/phone_agent_test.dart`
Expected: PASS (including the existing suite — open-source `content` already starts at `do(`, so `_actionLine` is a no-op there).

- [ ] **Step 5: Commit**

```bash
git add lib/src/agent/phone_agent.dart test/phone_agent_test.dart
git commit -m "feat(agent): store only the do() action line in history"
```

---

## Self-Review Notes

- **Spec coverage:** interface (T2), shared transport base (T2), three clients incl. AgentCPM retrofit (T3), prompts file with kOfficial derivation rules (T1), AgentConfig.systemPrompt removal + PhoneAgent client dependency + memory gate (T4), action-line history (T5), test migration enumerated (T4). All spec sections mapped.
- **Type consistency:** `AgentModelClient.chat` signature matches `ChatFn` (`{required List<LlmMessage> messages}`), so `client.chat` tear-offs still satisfy `DeepLocateActionRunner`'s `ChatFn` param. `withClient`/`withHttp` names: subclasses expose `.withClient`, base exposes `.withHttp` — subclass ctors forward via `super.withHttp(...)`.
- **No placeholders:** the only "PASTE verbatim" directives are deliberate verbatim copies of existing prompt text (must not be re-authored); derivation rules for `kOfficialPrompt` are explicit.
