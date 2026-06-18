import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger_utils/logger_utils.dart';

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

  /// Seam for injecting a [http.Client] (e.g. `MockClient`). Public production
  /// use is guarded one level up: each subclass exposes a `@visibleForTesting`
  /// `withClient` that forwards here.
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
    final rawBody = {
      'model': model,
      'messages': messages.map(_messageToJson).toList(),
      // autoglm-phone caps output at 2048 tokens; do not exceed it.
      'max_tokens': 2048,
      'frequency_penalty': 0.5,
      // 0.1 was prone to repetition collapse (runaway <think> hitting the token
      // cap → finish_reason="length"); 0.3 + top_p give room to escape the loop
      // without letting coordinate output diverge.
      'temperature': 0.3,
      'top_p': 0.7,
    };
    final body = jsonEncode(rawBody);

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
    devLogger.log(Level.INFO, prettyResponse(response));

    // A finish_reason other than "stop" means the output is not a clean,
    // complete answer — "length" = truncated by max_tokens (the trailing
    // finish()/action is likely cut off), "content_filter" = blocked. Surface
    // it so downstream parse failures are explainable rather than silent.
    final finishReason = choice['finish_reason'] as String?;
    if (finishReason != null && finishReason != 'stop') {
      _log.warning(
        '$model finish_reason="$finishReason" — output may be '
        'truncated or filtered; raise max_tokens or shorten the prompt.',
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
