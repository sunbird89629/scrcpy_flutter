import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrcpy_mcp/src/agent/clients/doubao_seed_client.dart';
import 'package:scrcpy_mcp/src/agent/clients/llm_client.dart';
import 'package:test/test.dart';

void main() {
  group('DoubaoSeedClient', () {
    DoubaoSeedClient makeClient(http.Client mockHttp) =>
        DoubaoSeedClient.withClient(
          baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
          apiKey: 'ark-test',
          model: 'doubao-seed-2-0-lite-260428',
          httpClient: mockHttp,
        );

    test('carries the do(...) prompt and no cross-step memory', () {
      final client = makeClient(
        MockClient((_) async => http.Response('', 200)),
      );
      expect(client.memoryEnabled, isFalse);
      // Reuses the official AutoGLM prompt: do(...) format, no XML wrappers.
      expect(client.systemPromptTemplate.contains('<think>'), isFalse);
      expect(client.systemPromptTemplate.contains('do(action='), isTrue);
    });

    test('sends correct Authorization header and full model id', () async {
      late http.Request captured;
      final client = makeClient(
        MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'role': 'assistant', 'content': 'ok'},
                },
              ],
            }),
            200,
          );
        }),
      );

      await client.chat(messages: <LlmMessage>[]);

      expect(captured.headers['Authorization'], 'Bearer ark-test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'doubao-seed-2-0-lite-260428');
    });

    test('includes image in user message', () async {
      late http.Request captured;
      final client = makeClient(
        MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'role': 'assistant', 'content': 'done'},
                },
              ],
            }),
            200,
          );
        }),
      );

      await client.chat(
        messages: [
          const LlmMessage(
            role: 'user',
            textContent: 'check the screen',
            imageBase64: 'abc123',
            imageMimeType: 'image/png',
          ),
        ],
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final msgs = body['messages'] as List<dynamic>;
      final content =
          (msgs.first as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content, hasLength(2));
      expect((content[1] as Map<String, dynamic>)['type'], 'image_url');
    });
  });
}
