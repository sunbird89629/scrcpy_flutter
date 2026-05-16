import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scrcpy_mcp/src/agent/llm_client.dart';
import 'package:scrcpy_mcp/src/agent/openai_llm_client.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiLlmClient', () {
    OpenAiLlmClient makeClient(http.Client mockHttp) => OpenAiLlmClient(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          model: 'gpt-4o',
          httpClient: mockHttp,
        );

    test('sends correct Authorization header and model', () async {
      late http.Request captured;
      final client = makeClient(MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'role': 'assistant', 'content': 'ok'},
              }
            ],
          }),
          200,
        );
      }));

      await client.chat(messages: [], tools: []);

      expect(captured.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o');
    });

    test('parses stop response as text', () async {
      final client = makeClient(MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'role': 'assistant', 'content': 'Task complete'},
                }
              ],
            }),
            200,
          )));

      final response = await client.chat(messages: [], tools: []);

      expect(response.isToolCall, isFalse);
      expect(response.text, 'Task complete');
    });

    test('parses tool_calls response', () async {
      final client = makeClient(MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'tool_calls',
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'call_abc',
                        'type': 'function',
                        'function': {
                          'name': 'take_screenshot',
                          'arguments': '{}',
                        },
                      }
                    ],
                  },
                }
              ],
            }),
            200,
          )));

      final response = await client.chat(messages: [], tools: []);

      expect(response.isToolCall, isTrue);
      expect(response.toolCalls!.first.name, 'take_screenshot');
      expect(response.toolCalls!.first.id, 'call_abc');
    });

    test('includes image in tool result message', () async {
      late http.Request captured;
      final client = makeClient(MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'role': 'assistant', 'content': 'done'},
              }
            ],
          }),
          200,
        );
      }));

      await client.chat(
        messages: [
          const LlmMessage(
            role: 'tool',
            textContent: 'res: 1264x2800',
            imageBase64: 'abc123',
            imageMimeType: 'image/png',
            toolCallId: 'c1',
          )
        ],
        tools: [],
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
      final client =
          makeClient(MockClient((_) async => http.Response('Unauthorized', 401)));

      await expectLater(
        client.chat(messages: [], tools: []),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
