import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logger_utils/logger_utils.dart';

import 'llm_client.dart';

final _log = Logger('scrcpy.mcp.llm');

class AutoglmLlmClient implements LlmClient {
  AutoglmLlmClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  factory AutoglmLlmClient.fromEnv() => AutoglmLlmClient(
    baseUrl: Platform.environment['AUTOGLM_BASE_URL']!,
    apiKey: Platform.environment['AUTOGLM_API_KEY']!,
    model: Platform.environment['AUTOGLM_MODEL']!,
  );

  factory AutoglmLlmClient.fromTest() => AutoglmLlmClient(
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    apiKey: 'dc45fcec2e1743f1ae732cf3b6e6ad17.tMejaXqUvJbJ5zZO',
    model: 'autoglm-phone',
  );

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
      'temperature': 0.1,
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

    // A finish_reason other than "stop" means the output is not a clean,
    // complete answer — "length" = truncated by max_tokens (the trailing
    // finish()/action is likely cut off), "content_filter" = blocked. Surface
    // it so downstream parse failures are explainable rather than silent.
    final finishReason = choice['finish_reason'] as String?;
    if (finishReason != null && finishReason != 'stop') {
      _log.warning(
        'autoglm-phone finish_reason="$finishReason" — output may be '
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
