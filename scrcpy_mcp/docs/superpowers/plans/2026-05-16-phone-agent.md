# Phone Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `run_task` MCP tool that accepts a natural-language instruction and executes it autonomously on an Android device via a ReAct agent loop driven by an OpenAI-compatible LLM.

**Architecture:** `RunTaskTool` wraps a `PhoneAgent` that loops: call LLM → execute tool calls (using existing scrcpy tools) → feed results back → repeat until LLM signals done or max steps reached. `ScrcpyMcpServer` gets optional `agentConfig`/`llmClient` params; when present, `run_task` is registered alongside existing tools.

**Tech Stack:** Dart, `package:http` (OpenAI HTTP client), `package:mcp_dart` (existing), `package:http/testing.dart` (test mocks)

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `lib/src/agent/agent_config.dart` | `AgentConfig` (maxSteps, systemPrompt) + `AgentResult` |
| Create | `lib/src/agent/llm_client.dart` | `LlmClient` abstract, `LlmMessage`, `LlmResponse`, `ToolCall`, `ToolSchema`, `LlmException` |
| Create | `lib/src/agent/openai_llm_client.dart` | `OpenAiLlmClient` — HTTP implementation of `LlmClient` |
| Create | `lib/src/agent/phone_agent.dart` | `PhoneAgent` — ReAct loop |
| Create | `lib/src/tools/run_task.dart` | `RunTaskTool` — MCP tool wrapping `PhoneAgent` |
| Modify | `lib/src/scrcpy_mcp_server.dart` | Add `agentConfig?`/`llmClient?` params; register `RunTaskTool` |
| Modify | `lib/scrcpy_mcp.dart` | Export new public types |
| Modify | `bin/scrcpy_mcp.dart` | Read env vars; construct agent if `OPENAI_API_KEY` present |
| Modify | `pubspec.yaml` | Add `http: ^1.2.0` dependency |
| Create | `test/openai_llm_client_test.dart` | Unit tests for HTTP client |
| Create | `test/phone_agent_test.dart` | Unit tests for ReAct loop |
| Create | `test/run_task_tool_test.dart` | Integration test via in-memory MCP transport |

---

## Task 1: Add `http` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add `http` to pubspec.yaml**

```yaml
dependencies:
  adb_tools:
    path: ../packages/adb_tools
  http: ^1.2.0
  logger_utils:
    path: ../packages/logger_utils
  mcp_dart: ^2.1.1
  scrcpy_client:
    path: ../packages/scrcpy_client
```

- [ ] **Step 2: Bootstrap workspace**

```bash
cd /Users/hao/ai/mobile/asf_dev && melos bootstrap
```

Expected: no errors, `http` package resolved.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_mcp/pubspec.yaml
git commit -m "chore(scrcpy_mcp): add http dependency for OpenAI client"
```

---

## Task 2: AgentConfig, LlmClient types, AgentResult

**Files:**
- Create: `lib/src/agent/agent_config.dart`
- Create: `lib/src/agent/llm_client.dart`

- [ ] **Step 1: Create `lib/src/agent/agent_config.dart`**

```dart
import 'dart:io';

const _kDefaultSystemPrompt = '''
你是一个 Android 设备控制助手，通过 scrcpy 协议操控手机。

规则：
1. 每步先截图了解当前界面，再决定下一步操作
2. 任务完成后直接用自然语言回复结果，不要再调用工具
3. 遇到无法完成的情况，说明原因后停止
4. 坐标使用截图返回的实际分辨率（width × height）
''';

class AgentConfig {
  const AgentConfig({
    this.maxSteps = 15,
    this.systemPrompt = _kDefaultSystemPrompt,
  });

  factory AgentConfig.fromEnv() => AgentConfig(
        maxSteps:
            int.tryParse(Platform.environment['SCRCPY_AGENT_MAX_STEPS'] ?? '') ??
                15,
      );

  final int maxSteps;
  final String systemPrompt;
}

class AgentResult {
  const AgentResult({
    required this.result,
    required this.steps,
    required this.success,
  });

  final String result;
  final int steps;
  final bool success;
}
```

- [ ] **Step 2: Create `lib/src/agent/llm_client.dart`**

```dart
/// A single tool call requested by the LLM.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments; // JSON-encoded argument map
}

/// JSON schema for one tool exposed to the LLM.
class ToolSchema {
  const ToolSchema({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters; // OpenAI-compatible JSON schema
}

/// A message in the LLM conversation history.
///
/// Supports multi-modal tool results: set [imageBase64] + [imageMimeType] when
/// a tool returned a screenshot so the LLM can see the screen.
class LlmMessage {
  const LlmMessage({
    required this.role,
    this.textContent,
    this.imageBase64,
    this.imageMimeType,
    this.toolCallId,
    this.toolCalls,
  });

  final String role; // 'system' | 'user' | 'assistant' | 'tool'
  final String? textContent;
  final String? imageBase64;
  final String? imageMimeType;
  final String? toolCallId; // present on 'tool' role messages
  final List<ToolCall>? toolCalls; // present on 'assistant' messages with tool calls
}

/// Response from the LLM.
class LlmResponse {
  const LlmResponse({this.text, this.toolCalls});

  final String? text;
  final List<ToolCall>? toolCalls;

  bool get isToolCall => toolCalls != null && toolCalls!.isNotEmpty;
}

/// Thrown when the LLM API returns an error or an unparseable response.
class LlmException implements Exception {
  const LlmException(this.message);
  final String message;

  @override
  String toString() => 'LlmException: $message';
}

/// Abstract LLM client — inject a fake in tests.
abstract class LlmClient {
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required List<ToolSchema> tools,
  });
}
```

- [ ] **Step 3: Run analyzer**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp && dart analyze lib/src/agent/
```

Expected: no errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_mcp/lib/src/agent/
git commit -m "feat(scrcpy_mcp): add AgentConfig, LlmClient types, AgentResult"
```

---

## Task 3: OpenAiLlmClient

**Files:**
- Create: `lib/src/agent/openai_llm_client.dart`
- Create: `test/openai_llm_client_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/openai_llm_client_test.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:scrcpy_mcp/src/agent/openai_llm_client.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiLlmClient', () {
    OpenAiLlmClient _client(http.Client mockHttp) => OpenAiLlmClient(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-4o',
          httpClient: mockHttp,
        );

    test('sends correct Authorization header and model', () async {
      late http.Request captured;
      final client = _client(MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'role': 'assistant', 'content': 'ok'},
              }
            ],
          }),
          200,
        );
      }));

      await client.chat(messages: [], tools: []);

      expect(captured.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o');
    });

    test('parses stop response as text', () async {
      final client = _client(MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'role': 'assistant', 'content': 'Task complete'},
                }
              ],
            }),
            200,
          )));

      final response = await client.chat(messages: [], tools: []);

      expect(response.isToolCall, isFalse);
      expect(response.text, 'Task complete');
    });

    test('parses tool_calls response', () async {
      final client = _client(MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'tool_calls',
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'call_abc',
                        'type': 'function',
                        'function': {
                          'name': 'take_screenshot',
                          'arguments': '{}',
                        },
                      }
                    ],
                  },
                }
              ],
            }),
            200,
          )));

      final response = await client.chat(messages: [], tools: []);

      expect(response.isToolCall, isTrue);
      expect(response.toolCalls!.first.name, 'take_screenshot');
      expect(response.toolCalls!.first.id, 'call_abc');
    });

    test('includes image in tool result message', () async {
      late http.Request captured;
      final client = _client(MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'role': 'assistant', 'content': 'done'},
              }
            ],
          }),
          200,
        );
      }));

      await client.chat(
        messages: [
          LlmMessage(
            role: 'tool',
            textContent: 'res: 1264x2800',
            imageBase64: 'abc123',
            imageMimeType: 'image/png',
            toolCallId: 'c1',
          )
        ],
        tools: [],
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final content =
          (body['messages'] as List).first['content'] as List<dynamic>;
      expect(content, hasLength(2));
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
    });

    test('throws LlmException on HTTP error', () async {
      final client =
          _client(MockClient((_) async => http.Response('Unauthorized', 401)));

      await expectLater(
        client.chat(messages: [], tools: []),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp && dart test test/openai_llm_client_test.dart
```

Expected: compile errors (file not found).

- [ ] **Step 3: Create `lib/src/agent/openai_llm_client.dart`**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

class OpenAiLlmClient implements LlmClient {
  OpenAiLlmClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  factory OpenAiLlmClient.fromEnv() => OpenAiLlmClient(
        baseUrl: Platform.environment['OPENAI_BASE_URL'] ??
            'https://api.openai.com/v1',
        apiKey: Platform.environment['OPENAI_API_KEY']!,
        model: Platform.environment['OPENAI_MODEL'] ?? 'gpt-4o',
      );

  static bool get isConfigured =>
      Platform.environment.containsKey('OPENAI_API_KEY');

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _http;

  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required List<ToolSchema> tools,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': messages.map(_messageToJson).toList(),
      if (tools.isNotEmpty) 'tools': tools.map(_toolToJson).toList(),
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
    final message = choice['message'] as Map<String, dynamic>;
    final finishReason = choice['finish_reason'] as String?;

    if (finishReason == 'tool_calls') {
      final rawCalls = message['tool_calls'] as List;
      return LlmResponse(
        toolCalls: rawCalls.map((c) {
          final fn = c['function'] as Map<String, dynamic>;
          return ToolCall(
            id: c['id'] as String,
            name: fn['name'] as String,
            arguments: fn['arguments'] as String,
          );
        }).toList(),
      );
    }

    return LlmResponse(text: message['content'] as String?);
  }

  Map<String, dynamic> _messageToJson(LlmMessage m) {
    final map = <String, dynamic>{'role': m.role};

    if (m.toolCallId != null) map['tool_call_id'] = m.toolCallId;

    if (m.toolCalls != null) {
      map['tool_calls'] = m.toolCalls!
          .map((tc) => {
                'id': tc.id,
                'type': 'function',
                'function': {'name': tc.name, 'arguments': tc.arguments},
              })
          .toList();
    }

    if (m.imageBase64 != null) {
      final parts = <Map<String, dynamic>>[];
      if (m.textContent != null) {
        parts.add({'type': 'text', 'text': m.textContent});
      }
      parts.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:${m.imageMimeType};base64,${m.imageBase64}',
        },
      });
      map['content'] = parts;
    } else if (m.textContent != null) {
      map['content'] = m.textContent;
    }

    return map;
  }

  Map<String, dynamic> _toolToJson(ToolSchema t) => {
        'type': 'function',
        'function': {
          'name': t.name,
          'description': t.description,
          'parameters': t.parameters,
        },
      };
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp && dart test test/openai_llm_client_test.dart
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/lib/src/agent/openai_llm_client.dart scrcpy_mcp/test/openai_llm_client_test.dart
git commit -m "feat(scrcpy_mcp): add OpenAiLlmClient with HTTP tests"
```

---

## Task 4: PhoneAgent — ReAct loop

**Files:**
- Create: `lib/src/agent/phone_agent.dart`
- Create: `test/phone_agent_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/phone_agent_test.dart`:

```dart
import 'package:scrcpy_mcp/src/agent/agent_config.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:scrcpy_mcp/src/agent/phone_agent.dart';
import 'package:test/test.dart';

// Fake that replays a fixed sequence of LlmResponse values.
class _FakeLlmClient implements LlmClient {
  _FakeLlmClient(this._responses);
  final List<LlmResponse> _responses;
  int _i = 0;

  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required List<ToolSchema> tools,
  }) async =>
      _responses[_i++];
}

void main() {
  group('PhoneAgent', () {
    PhoneAgent _agent(
      List<LlmResponse> responses, {
      ToolExecutor? executor,
      int maxSteps = 10,
    }) =>
        PhoneAgent(
          config: AgentConfig(maxSteps: maxSteps),
          llmClient: _FakeLlmClient(responses),
          tools: const [],
          executeToolCall: executor ??
              (_, __) async =>
                  (text: 'ok', imageBase64: null, imageMimeType: null),
        );

    test('returns success when LLM stops without tool calls', () async {
      final result = await _agent([
        LlmResponse(text: 'Task complete'),
      ]).run('open settings');

      expect(result.success, isTrue);
      expect(result.result, 'Task complete');
      expect(result.steps, 1);
    });

    test('executes tool calls before receiving final answer', () async {
      final executed = <String>[];
      final result = await _agent(
        [
          LlmResponse(toolCalls: [
            ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
          ]),
          LlmResponse(text: 'Done'),
        ],
        executor: (name, _) async {
          executed.add(name);
          return (text: 'screenshot taken', imageBase64: null, imageMimeType: null);
        },
      ).run('check screen');

      expect(result.success, isTrue);
      expect(executed, ['take_screenshot']);
      expect(result.steps, 2);
    });

    test('feeds tool result back into message history', () async {
      final capturingFake = _CapturingLlmClient([
        LlmResponse(toolCalls: [
          ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
        ]),
        LlmResponse(text: 'Done'),
      ]);

      final capturingAgent = PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        llmClient: capturingFake,
        tools: const [],
        executeToolCall: (_, __) async =>
            (text: 'res: 1264x2800', imageBase64: null, imageMimeType: null),
      );

      await capturingAgent.run('check screen');

      // Second call should include tool result in history
      final secondCallMessages = capturingFake.capturedMessages[1];
      expect(secondCallMessages.any((m) => m.role == 'tool'), isTrue);
      final toolMsg =
          secondCallMessages.firstWhere((m) => m.role == 'tool');
      expect(toolMsg.textContent, 'res: 1264x2800');
      expect(toolMsg.toolCallId, 'c1');
    });

    test('returns failure when max steps reached', () async {
      final result = await _agent(
        List.generate(
          3,
          (_) => LlmResponse(toolCalls: [
            ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
          ]),
        ),
        maxSteps: 3,
      ).run('impossible task');

      expect(result.success, isFalse);
      expect(result.steps, 3);
      expect(result.result, contains('Max steps'));
    });

    test('continues loop when tool execution throws', () async {
      final result = await _agent(
        [
          LlmResponse(toolCalls: [
            ToolCall(id: 'c1', name: 'bad_tool', arguments: '{}'),
          ]),
          LlmResponse(text: 'Recovered after error'),
        ],
        executor: (_, __) async => throw Exception('network fail'),
      ).run('test recovery');

      expect(result.success, isTrue);
      expect(result.result, 'Recovered after error');
    });

    test('includes image in tool result message when executor returns one',
        () async {
      final capturingFake = _CapturingLlmClient([
        LlmResponse(toolCalls: [
          ToolCall(id: 'c1', name: 'take_screenshot', arguments: '{}'),
        ]),
        LlmResponse(text: 'Done'),
      ]);

      await PhoneAgent(
        config: const AgentConfig(maxSteps: 5),
        llmClient: capturingFake,
        tools: const [],
        executeToolCall: (_, __) async => (
          text: 'res: 1264x2800',
          imageBase64: 'base64png',
          imageMimeType: 'image/png',
        ),
      ).run('screenshot test');

      final toolMsg = capturingFake.capturedMessages[1]
          .firstWhere((m) => m.role == 'tool');
      expect(toolMsg.imageBase64, 'base64png');
      expect(toolMsg.imageMimeType, 'image/png');
    });
  });
}

class _CapturingLlmClient implements LlmClient {
  _CapturingLlmClient(this._responses);
  final List<LlmResponse> _responses;
  final capturedMessages = <List<LlmMessage>>[];
  int _i = 0;

  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required List<ToolSchema> tools,
  }) async {
    capturedMessages.add(List.from(messages));
    return _responses[_i++];
  }
}
```

- [ ] **Step 2: Run tests — expect compile failures**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp && dart test test/phone_agent_test.dart
```

Expected: compile error (`phone_agent.dart` not found, `ToolExecutor` not defined).

- [ ] **Step 3: Create `lib/src/agent/phone_agent.dart`**

```dart
import 'dart:convert';

import 'agent_config.dart';
import 'llm_client.dart';

/// Callback that executes one tool call and returns text + optional image.
typedef ToolExecutor = Future<
    ({String text, String? imageBase64, String? imageMimeType})> Function(
  String name,
  Map<String, dynamic> args,
);

/// ReAct agent: loops think → act → observe until the LLM stops calling tools
/// or [AgentConfig.maxSteps] is exhausted.
class PhoneAgent {
  const PhoneAgent({
    required this.config,
    required this.llmClient,
    required this.tools,
    required this.executeToolCall,
  });

  final AgentConfig config;
  final LlmClient llmClient;
  final List<ToolSchema> tools;
  final ToolExecutor executeToolCall;

  Future<AgentResult> run(String message) async {
    final messages = <LlmMessage>[
      LlmMessage(role: 'system', textContent: config.systemPrompt),
      LlmMessage(role: 'user', textContent: message),
    ];

    for (var step = 0; step < config.maxSteps; step++) {
      final response =
          await llmClient.chat(messages: messages, tools: tools);

      if (!response.isToolCall) {
        return AgentResult(
          result: response.text ?? '',
          steps: step + 1,
          success: true,
        );
      }

      // Append assistant's tool-call message
      messages.add(LlmMessage(
        role: 'assistant',
        toolCalls: response.toolCalls,
      ));

      // Execute each tool call, append result
      for (final call in response.toolCalls!) {
        final result = await _safeExecute(call);
        messages.add(LlmMessage(
          role: 'tool',
          textContent: result.text,
          imageBase64: result.imageBase64,
          imageMimeType: result.imageMimeType,
          toolCallId: call.id,
        ));
      }
    }

    return AgentResult(
      result: 'Max steps (${config.maxSteps}) reached without completing the task.',
      steps: config.maxSteps,
      success: false,
    );
  }

  Future<({String text, String? imageBase64, String? imageMimeType})>
      _safeExecute(ToolCall call) async {
    try {
      final args = jsonDecode(call.arguments) as Map<String, dynamic>;
      return await executeToolCall(call.name, args);
    } catch (e) {
      return (text: 'Error: $e', imageBase64: null, imageMimeType: null);
    }
  }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp && dart test test/phone_agent_test.dart
```

Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add scrcpy_mcp/lib/src/agent/phone_agent.dart scrcpy_mcp/test/phone_agent_test.dart
git commit -m "feat(scrcpy_mcp): add PhoneAgent ReAct loop with unit tests"
```

---

## Task 5: RunTaskTool

**Files:**
- Create: `lib/src/tools/run_task.dart`
- Create: `test/run_task_tool_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/run_task_tool_test.dart`:

```dart
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/src/agent/agent_config.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:test/test.dart';

import 'real_device_test_utils.dart';

// Fake LLM that immediately returns "Done" with no tool calls.
class _DoneLlmClient implements LlmClient {
  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required List<ToolSchema> tools,
  }) async =>
      LlmResponse(text: 'Task done');
}

void main() {
  group('run_task tool', () {
    late McpClient client;
    late Future<void> Function() close;

    setUp(() async {
      final server = ScrcpyMcpServer(
        session: MockScrcpySession(),
        adb: MockAdb(),
        agentConfig: const AgentConfig(maxSteps: 5),
        llmClient: _DoneLlmClient(),
      );
      (client, close) = await connectMcpPair(server);
    });

    tearDown(() => close());

    test('run_task tool is advertised', () async {
      final tools = await client.listTools();
      expect(tools.tools.map((t) => t.name), contains('run_task'));
    });

    test('run_task returns success result', () async {
      final result = await client.callTool(
        CallToolRequest(
          name: 'run_task',
          arguments: {
            'device_id': 'device1',
            'message': 'open settings',
          },
        ),
      );

      expect(result.isError, isFalse);
      final json =
          jsonDecode((result.content.first as TextContent).text) as Map;
      expect(json['success'], isTrue);
      expect(json['result'], 'Task done');
      expect(json['steps'], 1);
    });

    test('run_task not advertised when no agent config', () async {
      final serverNoAgent = ScrcpyMcpServer(
        session: MockScrcpySession(),
        adb: MockAdb(),
      );
      final (clientNoAgent, closeNoAgent) =
          await connectMcpPair(serverNoAgent);
      addTearDown(closeNoAgent);

      final tools = await clientNoAgent.listTools();
      expect(tools.tools.map((t) => t.name), isNot(contains('run_task')));
    });
  });
}
```

- [ ] **Step 2: Run test — expect failure**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp && dart test test/run_task_tool_test.dart
```

Expected: compile error (`run_task.dart` not found, `ScrcpyMcpServer` missing `agentConfig` param).

- [ ] **Step 3: Create `lib/src/tools/run_task.dart`**

```dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../agent/agent_config.dart';
import '../agent/llm_client.dart';
import '../agent/phone_agent.dart';
import '../mcp_tool.dart';
import '../session_context.dart';

class RunTaskTool extends McpTool {
  RunTaskTool({
    required AgentConfig config,
    required LlmClient llmClient,
    required List<McpTool> tools,
    required ScrcpySession session,
    required SessionContext ctx,
  })  : _config = config,
        _llmClient = llmClient,
        _tools = tools,
        _session = session,
        _ctx = ctx;

  final AgentConfig _config;
  final LlmClient _llmClient;
  final List<McpTool> _tools;
  final ScrcpySession _session;
  final SessionContext _ctx;

  @override
  String get name => 'run_task';

  @override
  String get description =>
      'Run a natural language task on an Android device using an AI agent. '
      'The agent autonomously takes screenshots, taps, and types to complete '
      'the task, then returns a plain-text result.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'device_id': JsonSchema.string(
        description: 'Device serial to operate on (from list_devices)',
      ),
      'message': JsonSchema.string(
        description: 'Natural language task, e.g. "打开微信" or "查询违章信息"',
      ),
    },
    required: ['device_id', 'message'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceId = args['device_id'] as String;
    final message = args['message'] as String;

    if (!_session.isConnected) {
      await _session.start(deviceId);
      _ctx.connectedDeviceId = deviceId;
    }

    final toolMap = {for (final t in _tools) t.name: t};
    final toolSchemas = _tools
        .map((t) => ToolSchema(
              name: t.name,
              description: t.description,
              parameters: t.inputSchema,
            ))
        .toList();

    Future<({String text, String? imageBase64, String? imageMimeType})>
        execTool(String toolName, Map<String, dynamic> toolArgs) async {
      final tool = toolMap[toolName];
      if (tool == null) {
        return (
          text: 'Error: unknown tool "$toolName"',
          imageBase64: null,
          imageMimeType: null,
        );
      }
      final result = await tool.execute(toolArgs, extra);
      if (result.isError) {
        final errText = result.content
            .whereType<TextContent>()
            .map((c) => c.text)
            .join('\n');
        return (text: 'Error: $errText', imageBase64: null, imageMimeType: null);
      }
      String? imgBase64;
      String? imgMime;
      final textParts = <String>[];
      for (final content in result.content) {
        if (content is TextContent) textParts.add(content.text);
        if (content is ImageContent) {
          imgBase64 = content.data;
          imgMime = content.mimeType;
        }
      }
      return (
        text: textParts.join('\n'),
        imageBase64: imgBase64,
        imageMimeType: imgMime,
      );
    }

    final agent = PhoneAgent(
      config: _config,
      llmClient: _llmClient,
      tools: toolSchemas,
      executeToolCall: execTool,
    );

    try {
      final result = await agent.run(message);
      return CallToolResult.fromStructuredContent({
        'result': result.result,
        'steps': result.steps,
        'success': result.success,
      });
    } catch (e) {
      return CallToolResult.fromStructuredContent({
        'result': e.toString(),
        'steps': 0,
        'success': false,
      });
    }
  }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp && dart test test/run_task_tool_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/lib/src/tools/run_task.dart scrcpy_mcp/test/run_task_tool_test.dart
git commit -m "feat(scrcpy_mcp): add RunTaskTool wrapping PhoneAgent"
```

---

## Task 6: Wire ScrcpyMcpServer + bin/scrcpy_mcp.dart + exports

**Files:**
- Modify: `lib/src/scrcpy_mcp_server.dart`
- Modify: `bin/scrcpy_mcp.dart`
- Modify: `lib/scrcpy_mcp.dart`

- [ ] **Step 1: Update `ScrcpyMcpServer` constructor**

In `lib/src/scrcpy_mcp_server.dart`, add imports and optional parameters:

```dart
// Add these imports at the top:
import 'agent/agent_config.dart';
import 'agent/llm_client.dart';
import 'tools/run_task.dart' show RunTaskTool;
```

Replace the constructor:

```dart
ScrcpyMcpServer({
  required ScrcpySession session,
  required ScrcpyAdb adb,
  RecordingAdb? recordingAdb,
  AgentConfig? agentConfig,   // NEW
  LlmClient? llmClient,       // NEW
})  : _session = session,
      _adb = adb,
      _agentConfig = agentConfig,
      _llmClient = llmClient,
      _ctx = SessionContext() {
  // ... rest unchanged
}
```

Add fields:

```dart
final AgentConfig? _agentConfig;
final LlmClient? _llmClient;
```

- [ ] **Step 2: Register RunTaskTool inside `_registerTools()`**

At the end of the `tools` list construction in `_registerTools()`, before the `for` loop, add:

```dart
// Agent tool — only when both config and client are provided.
// Built AFTER all other tools so it can reference their schemas.
if (_agentConfig != null && _llmClient != null) {
  tools.add(RunTaskTool(
    config: _agentConfig!,
    llmClient: _llmClient!,
    tools: List.unmodifiable(tools), // snapshot before adding run_task itself
    session: _session,
    ctx: _ctx,
  ));
}
```

- [ ] **Step 3: Update `bin/scrcpy_mcp.dart`**

```dart
#!/usr/bin/env dart

import 'dart:io';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

void main(List<String> args) async {
  initLogging();
  final adbPath = args.isNotEmpty ? args[0] : 'adb';
  final adb = AdbClient(adbPath: adbPath);
  final scrcpyAdb = ScrcpyMcpAdb(adb);

  final session = await ScrcpySessionImpl.create(adb: scrcpyAdb);

  final agentConfig = OpenAiLlmClient.isConfigured
      ? AgentConfig.fromEnv()
      : null;
  final llmClient = OpenAiLlmClient.isConfigured
      ? OpenAiLlmClient.fromEnv()
      : null;

  if (agentConfig != null) {
    appLogger.info('Agent enabled: model=${llmClient!.model}, '
        'maxSteps=${agentConfig.maxSteps}');
  }

  final server = ScrcpyMcpServer(
    session: session,
    adb: scrcpyAdb,
    recordingAdb: scrcpyAdb,
    agentConfig: agentConfig,
    llmClient: llmClient,
  );

  final transport = StdioServerTransport();
  await server.mcpServer.connect(transport);
}
```

- [ ] **Step 4: Update `lib/scrcpy_mcp.dart` exports**

Add to the export list:

```dart
export 'src/agent/agent_config.dart';
export 'src/agent/llm_client.dart';
export 'src/agent/openai_llm_client.dart';
export 'src/agent/phone_agent.dart';
```

- [ ] **Step 5: Run all tests**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp && dart test
```

Expected: all existing tests + new tests pass. Tool count in `scrcpy_mcp_server_test.dart` may need updating — if a test asserts an exact tool count (e.g. `expect(tools.tools.length, 21)`), update it to the new count (existing count + 1 for `run_task` when agent is provided, or same count when no agent).

- [ ] **Step 6: Run analyzer**

```bash
cd /Users/hao/ai/mobile/asf_dev && dart analyze scrcpy_mcp/
```

Expected: no errors, no warnings.

- [ ] **Step 7: Commit**

```bash
git add scrcpy_mcp/lib/src/scrcpy_mcp_server.dart \
        scrcpy_mcp/lib/scrcpy_mcp.dart \
        scrcpy_mcp/bin/scrcpy_mcp.dart
git commit -m "feat(scrcpy_mcp): wire PhoneAgent into ScrcpyMcpServer and CLI entry point"
```

---

## Task 7: Real device integration test

**Files:**
- Create: `test/real_device_agent_test.dart`

- [ ] **Step 1: Create `test/real_device_agent_test.dart`**

```dart
/// Real-device integration test for run_task.
///
/// Requires:
///   - A connected Android device
///   - OPENAI_API_KEY env var set
///   - SCRCPY_MCP_TEST_DEVICE env var set to the device serial
///
/// Run with:
///   dart test test/real_device_agent_test.dart
@TestOn('vm')
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'real_device_test_utils.dart';

void main() {
  final deviceId = const String.fromEnvironment('SCRCPY_MCP_TEST_DEVICE');
  final hasApiKey = OpenAiLlmClient.isConfigured;

  group(
    'run_task real device',
    () {
      late McpClient client;
      late Future<void> Function() close;

      setUpAll(() async {
        final scrcpyAdb = ScrcpyMcpAdb(AdbClient());
        final session = await ScrcpySessionImpl.create(adb: scrcpyAdb);

        final server = ScrcpyMcpServer(
          session: session,
          adb: scrcpyAdb,
          agentConfig: AgentConfig.fromEnv(),
          llmClient: OpenAiLlmClient.fromEnv(),
        );
        (client, close) = await connectMcpPair(server);
      });

      tearDownAll(() => close());

      test('run_task completes a simple task', () async {
        final result = await client.callTool(
          CallToolRequest(
            name: 'run_task',
            arguments: {
              'device_id': deviceId,
              'message': '截一张屏幕截图并描述当前界面',
            },
          ),
        );
        expect(result.isError, isFalse);
      }, timeout: const Timeout(Duration(minutes: 2)));
    },
    skip: (!hasApiKey || deviceId.isEmpty)
        ? 'Set OPENAI_API_KEY and SCRCPY_MCP_TEST_DEVICE to run'
        : null,
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add scrcpy_mcp/test/real_device_agent_test.dart
git commit -m "test(scrcpy_mcp): add real device integration test for run_task"
```
