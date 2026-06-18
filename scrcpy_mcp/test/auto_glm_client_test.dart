import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrcpy_mcp/src/agent/auto_glm_client.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:test/test.dart';

void main() {
  group('AutoGLMOfficialClient', () {
    AutoGLMOfficialClient makeClient(http.Client mockHttp) =>
        AutoGLMOfficialClient.withClient(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-4o',
          httpClient: mockHttp,
        );

    test('carries the official (no-tag) prompt and no cross-step memory', () {
      final client = makeClient(MockClient((_) async => http.Response('', 200)));
      expect(client.memoryEnabled, isFalse);
      expect(client.systemPromptTemplate.contains('<think>'), isFalse);
      expect(client.systemPromptTemplate.contains('<answer>'), isFalse);
    });

    test('open-source client carries the tag prompt and cross-step memory', () {
      final client = AutoGLMOpenSourceClient.withClient(
        baseUrl: 'https://x/api',
        apiKey: 'k',
        model: 'AutoGLM-Phone-9B',
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      expect(client.memoryEnabled, isTrue);
      expect(client.systemPromptTemplate.contains('<answer>'), isTrue);
    });

    test('sends correct Authorization header and model', () async {
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

      expect(captured.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o');
    });

    test('parses text response', () async {
      final client = makeClient(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'role': 'assistant', 'content': 'Task complete'},
                },
              ],
            }),
            200,
          ),
        ),
      );

      final response = await client.chat(messages: <LlmMessage>[]);

      expect(response.text, 'Task complete');
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
      expect((content[0] as Map<String, dynamic>)['type'], 'text');
      expect((content[1] as Map<String, dynamic>)['type'], 'image_url');
    });

    test('throws LlmException on HTTP error', () async {
      final client = makeClient(
        MockClient((_) async => http.Response('Unauthorized', 401)),
      );

      await expectLater(
        client.chat(messages: <LlmMessage>[]),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
