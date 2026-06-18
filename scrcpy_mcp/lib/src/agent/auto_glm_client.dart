import 'dart:io';

import 'package:meta/meta.dart';

import 'agent_prompts.dart';
import 'openai_chat_client.dart';

/// bigmodel-hosted autoglm-phone. Emits inline prose + a bare `do(...)` line;
/// ignores `<think>/<answer>/<memory>` wrappers and has no cross-step memory.
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
    required super.httpClient,
  }) : super.withHttp();

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

/// Self-hosted open-source AutoGLM-Phone-9B (arch = GLM-4.1V-9B-Thinking). Uses
/// the `<think>/<answer>/<memory>` format and supports cross-step memory.
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
    required super.httpClient,
  }) : super.withHttp();

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
