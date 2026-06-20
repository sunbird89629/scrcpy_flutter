import 'dart:io';

import 'package:meta/meta.dart';

import '../agent_prompts.dart';
import 'openai_chat_client.dart';

/// Volcano Ark (火山方舟) Doubao-Seed vision model, e.g. `doubao-seed-2-0-lite`.
/// A strong-grounding general VLM exposed over an OpenAI-compatible endpoint, so
/// it reuses [OpenAiChatClient] transport and the official AutoGLM `do(...)`
/// prompt ([kOfficialPrompt], coordinate space [0,1000]) — no response
/// translation needed, the shared `ResponseParser` handles its output as-is.
class DoubaoSeedClient extends OpenAiChatClient {
  DoubaoSeedClient({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
  });

  @visibleForTesting
  DoubaoSeedClient.withClient({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required super.httpClient,
  }) : super.withHttp();

  /// Default Volcano Ark endpoint; override with `DOUBAO_BASE_URL`.
  static const defaultBaseUrl =
      'https://ark.cn-beijing.volces.com/api/coding/v3';

  /// `DOUBAO_MODEL` must be the full versioned Model ID (e.g.
  /// `doubao-seed-2-0-lite-260428`) — the short name returns HTTP 404.
  factory DoubaoSeedClient.fromEnv() => DoubaoSeedClient(
    baseUrl: Platform.environment['DOUBAO_BASE_URL'] ?? defaultBaseUrl,
    apiKey: Platform.environment['DOUBAO_API_KEY']!,
    model: Platform.environment['DOUBAO_MODEL']!,
  );

  factory DoubaoSeedClient.fromTest() => DoubaoSeedClient(
    baseUrl: 'https://ark.cn-beijing.volces.com/api/coding/v3',
    apiKey: 'ark-71cf1e4a-1520-47aa-aa62-f5a5f6ff652b-12721',
    model: 'doubao-seed-2-0-lite-260428',
  );

  @override
  String get systemPromptTemplate => kOfficialPrompt;

  @override
  bool get memoryEnabled => false;
}
