import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

/// Client for AgentCPM-GUI (Tsinghua OpenBMB) on ModelScope or any
/// OpenAI-compatible endpoint.
///
/// Output format: compact JSON, e.g. `{"POINT":[729,69]}`
/// Coordinate space: 0-1000, top-left origin.
class AgentCPMGuiClient {
  AgentCPMGuiClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _http;

  /// Standard [ChatFn] so this can be passed directly as
  /// `PhoneAgent(llmClient: client.chat)` after format adaptation.
  Future<LlmResponse> chat({required List<LlmMessage> messages}) async {
    // AgentCPM-GUI expects a specific format:
    // System: role/rule/schema (injected into user message as per the paper)
    // User: <Question>instruction</Question>\n当前屏幕截图： + image
    // It outputs compact JSON with POINT/PRESS/TYPE/STATUS

    final userMsg = messages.lastWhere((m) => m.role == 'user');

    // Extract instruction from the last user message
    final instruction = userMsg.textContent ?? '';

    final openAiMessages = <Map<String, Object?>>[];

    // System prompt with schema
    openAiMessages.add({'role': 'system', 'content': _systemPrompt});

    // User: format with <Question> tag + image
    final userContent = <Map<String, Object?>>[];
    userContent.add({
      'type': 'text',
      'text': '<Question>$instruction</Question>\n当前屏幕截图：',
    });
    if (userMsg.imageBase64 != null) {
      userContent.add({
        'type': 'image_url',
        'image_url': {
          'url':
              'data:${userMsg.imageMimeType ?? 'image/png'};base64,${userMsg.imageBase64}',
        },
      });
    }
    openAiMessages.add({'role': 'user', 'content': userContent});

    final uri = Uri.parse('$baseUrl/chat/completions');
    final response = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': openAiMessages,
        'temperature': 0.1,
        'top_p': 0.3,
        'max_tokens': 512,
      }),
    );

    if (response.statusCode != 200) {
      return LlmResponse(
        text: 'API error ${response.statusCode}: ${response.body}',
        finishReason: 'error',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return const LlmResponse(text: '', finishReason: 'stop');
    }

    final rawText = (choices[0]['message']?['content'] ?? '') as String;
    final finishReason = choices[0]['finish_reason'] as String?;

    // Convert AgentCPM-GUI JSON output → AutoGLM-format text
    // so ResponseParser can handle it unchanged
    final translated = _translateAction(rawText.trim());

    return LlmResponse(text: translated, finishReason: finishReason);
  }

  /// Translate AgentCPM-GUI JSON output to AutoGLM-compatible format.
  String _translateAction(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      // STATUS field
      final status = json['STATUS'] as String?;
      if (status == 'finish' || status == 'satisfied') {
        return 'finish(message="done")';
      }
      if (status == 'impossible') {
        return 'finish(message="任务无法完成")';
      }

      // POINT → Tap (convert AgentCPM's [x,y] to element=[x,y])
      final point = json['POINT'] as List<dynamic>?;
      if (point != null && point.length == 2) {
        final x = point[0];
        final y = point[1];

        // Check if this is a swipe (has 'to' field)
        final to = json['to'];
        if (to is List && to.length == 2) {
          final ex = to[0] as int;
          final ey = to[1] as int;
          return 'do(action="Swipe", start=[$x,$y], end=[$ex,$ey])';
        }
        if (to is String) {
          final delta = _swipeDelta(to);
          final ex = (x + delta.dx).clamp(0, 1000) as int;
          final ey = (y + delta.dy).clamp(0, 1000) as int;
          return 'do(action="Swipe", start=[$x,$y], end=[$ex,$ey])';
        }

        // Regular tap
        return 'do(action="Tap", element=[$x,$y])';
      }

      // PRESS → Back/Home
      final press = json['PRESS'] as String?;
      if (press == 'BACK') return 'do(action="Back")';
      if (press == 'HOME') return 'do(action="Home")';
      if (press == 'ENTER') return 'do(action="Enter")';

      // TYPE → Type
      final type = json['TYPE'] as String?;
      if (type != null) return 'do(action="Type", text="$type")';

      // duration-only → Wait
      final duration = json['duration'];
      if (duration is num && point == null) {
        return 'do(action="Wait", duration="${(duration / 1000).round()} seconds")';
      }

      // Fallback
      return 'finish(message="$raw")';
    } catch (_) {
      // Not JSON — try to extract POINT/TAP from free text
      return _heuristicParse(raw);
    }
  }

  ({int dx, int dy}) _swipeDelta(String direction) => switch (direction) {
    'up' => (dx: 0, dy: -300),
    'down' => (dx: 0, dy: 300),
    'left' => (dx: -300, dy: 0),
    'right' => (dx: 300, dy: 0),
    _ => (dx: 0, dy: 0),
  };

  String _heuristicParse(String raw) {
    // Try to find POINT:[x,y] pattern
    final pointRe = RegExp(r'POINT.*?\[(\d+)\s*,\s*(\d+)\]');
    final pm = pointRe.firstMatch(raw);
    if (pm != null) {
      return 'do(action="Tap", element=[${pm.group(1)},${pm.group(2)}])';
    }
    if (raw.contains('finish') || raw.contains('STATUS')) {
      return 'finish(message="done")';
    }
    return raw;
  }

  static const _systemPrompt = '''
# Role
你是一名熟悉安卓系统触屏GUI操作的智能体，将根据用户的问题，分析当前界面的GUI元素和布局，生成相应的操作。

# Task
针对用户问题，根据输入的当前屏幕截图，输出下一步的操作。

# Rule
- 以紧凑JSON格式输出
- 输出操作必须遵循Schema约束

# Schema
{"type":"object","properties":{"thought":{"type":"string","description":"推理过程"},"POINT":{"type":"array","description":"坐标为相对于屏幕左上角为原点的相对位置，按照宽高比例缩放到0~1000，数组第一个元素为横坐标x，第二个元素为纵坐标y","items":{"type":"integer","minimum":0,"maximum":1000},"minItems":2,"maxItems":2},"TYPE":{"type":"string","description":"输入文本内容"},"PRESS":{"type":"string","enum":["HOME","BACK","ENTER"],"description":"按键操作"},"duration":{"type":"integer","description":"等待时长，单位为毫秒"},"to":{"description":"滑动方向(up/down/left/right)或目标坐标[x,y]"},"STATUS":{"type":"string","enum":["finish","satisfied","impossible","start","continue","interrupt","need_feedback"],"description":"任务状态"}}}
''';
}
