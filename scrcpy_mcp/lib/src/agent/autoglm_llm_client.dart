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
    baseUrl:
        Platform.environment['AUTOGLM_BASE_URL'] ?? 'https://open.bigmodel.cn/api/paas/v4',
    apiKey: Platform.environment['AUTOGLM_API_KEY']!,
    model: Platform.environment['AUTOGLM_MODEL'] ?? 'autoglm-phone',
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
      'max_tokens': 3000,
      'frequency_penalty': 0.5,
      'temperature': 0.1,
    };
    final body = jsonEncode(rawBody);

    _log.infoJson('→ POST $uri', _summarizeBody(rawBody));

    final response = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );

    _log.infoJson('← HTTP ${response.statusCode}', response.body);

    if (response.statusCode != 200) {
      throw LlmException('HTTP ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choice = (json['choices'] as List).first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>;

    return LlmResponse(text: message['content'] as String?);
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

  /// Returns a copy of [body] with base64 images truncated to keep logs
  /// readable.
  static Map<String, dynamic> _summarizeBody(Map<String, dynamic> body) {
    final copy = Map<String, dynamic>.from(body);
    final msgs = (copy['messages'] as List).cast<Map<String, dynamic>>();
    copy['messages'] = msgs.map((m) {
      final content = m['content'];
      if (content is List) {
        return {
          ...m,
          'content': content.map((part) {
            if (part is Map && part['type'] == 'image_url') {
              final url = (part['image_url'] as Map)['url'] as String? ?? '';
              return {
                ...part,
                'image_url': {
                  'url': url.length > 80
                      ? '${url.substring(0, 80)}...<truncated>'
                      : url,
                },
              };
            }
            return part;
          }).toList(),
        };
      }
      return m;
    }).toList();
    return copy;
  }
}
