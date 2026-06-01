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
  final List<ToolCall>?
  toolCalls; // present on 'assistant' messages with tool calls
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
