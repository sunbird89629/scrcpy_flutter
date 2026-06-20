/// A message in the LLM conversation history.
///
/// Supports multi-modal: set [imageBase64] + [imageMimeType] to pass a
/// screenshot to the vision model.
class LlmMessage {
  const LlmMessage({
    required this.role,
    this.textContent,
    this.imageBase64,
    this.imageMimeType,
  });

  final String role; // 'system' | 'user' | 'assistant'
  final String? textContent;
  final String? imageBase64;
  final String? imageMimeType;
  @override
  String toString() {
    return 'LlmMessage('
        'role: $role, '
        'textContent: $textContent, '
        'hasImage: ${imageBase64 != null}, '
        'imageMimeType: $imageMimeType'
        ')';
  }
}

/// Response from the LLM.
class LlmResponse {
  const LlmResponse({this.text, this.finishReason});
  final String? text;

  /// Why generation stopped: 'stop' (clean), 'length' (truncated by max_tokens),
  /// 'content_filter', etc. Null when the client doesn't report it.
  final String? finishReason;
}

/// Thrown when the LLM API returns an error or an unparseable response.
class LlmException implements Exception {
  const LlmException(this.message);
  final String message;

  @override
  String toString() => 'LlmException: $message';
}

/// Signature for sending a chat-completion request.
typedef ChatFn =
    Future<LlmResponse> Function({required List<LlmMessage> messages});
