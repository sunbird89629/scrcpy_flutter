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
  /// Default Volcano Ark endpoint; override with `DOUBAO_BASE_URL`.
  ///
  /// Must be the standard `/api/v3` endpoint, NOT the Coding Plan
  /// `/api/coding/v3` one: the Coding Plan endpoint rejects image input with a
  /// generic `InvalidParameter` 400, and the phone agent sends a screenshot
  /// every step.
  static const defaultBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
  static const arkApiKey = 'ark-71cf1e4a-1520-47aa-aa62-f5a5f6ff652b-12721';
  static const arkModel = 'doubao-seed-2-0-lite-260428';

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

  /// `DOUBAO_MODEL` must be the full versioned Model ID (e.g.
  /// `doubao-seed-2-0-lite-260428`) — the short name returns HTTP 404.
  factory DoubaoSeedClient.fromEnv() => DoubaoSeedClient(
    baseUrl: Platform.environment['DOUBAO_BASE_URL']!,
    apiKey: Platform.environment['DOUBAO_API_KEY']!,
    model: Platform.environment['DOUBAO_MODEL']!,
  );

  factory DoubaoSeedClient.fromTest() => DoubaoSeedClient(
    baseUrl: defaultBaseUrl,
    apiKey: arkApiKey,
    model: arkModel,
  );

  @override
  String get systemPromptTemplate => kOfficialPrompt;

  @override
  bool get memoryEnabled => false;
}
