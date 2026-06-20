import 'llm_client.dart';

/// A self-contained adapter for one GUI model: owns its system prompt and
/// transport so model differences live at the client boundary. `PhoneAgent`
/// depends only on this interface.
abstract interface class AgentModelClient {
  /// System prompt with `{DATE}`/`{SCREEN_SIZE}` placeholders; `PhoneAgent`
  /// substitutes runtime values before sending.
  String get systemPromptTemplate;

  /// Whether the model emits cross-step `<memory>` entries.
  bool get memoryEnabled;

  Future<LlmResponse> chat({required List<LlmMessage> messages});
}
