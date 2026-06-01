import 'dart:convert';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

const _deviceId = '39111FDJH00D47';

/// Sends a screenshot to the autoglm model and asks whether it contains
/// [expected]. Returns the model's raw response text.
Future<String> _askModel(
  AutoglmLlmClient client,
  String base64Screenshot,
  String expected,
) async {
  final response = await client.chat(
    messages: [
      const LlmMessage(
        role: 'system',
        textContent:
            '你是一个手机界面分析助手。请根据截图回答用户的问题。'
            '回答要简洁，只回答"是"或"否"，并附带简短说明。',
      ),
      LlmMessage(
        role: 'user',
        textContent: '截图中是否包含"$expected"相关的内容或界面？',
        imageBase64: base64Screenshot,
        imageMimeType: 'image/png',
      ),
    ],
  );
  return response.text ?? '';
}

void main() {
  test(
    'screenshot contains app icons',
    () async {
      initLogging();
      final adb = ScrcpyMcpAdb(AdbClient());
      final client = AutoglmLlmClient.fromTest();

      final bytes = await adb.takeScreenshot(_deviceId);
      final screenshot = base64Encode(bytes);

      final response = await _askModel(client, screenshot, '应用图标');

      expect(response, isNotEmpty);
      expect(response, contains('是'));
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: false,
  );

  test(
    'screenshot answer for non-existent content',
    () async {
      initLogging();
      final adb = ScrcpyMcpAdb(AdbClient());
      final client = AutoglmLlmClient.fromTest();

      final bytes = await adb.takeScreenshot(_deviceId);
      final screenshot = base64Encode(bytes);

      // Desktop should not contain a calculator app specifically
      final response = await _askModel(client, screenshot, '计算器');

      expect(response, isNotEmpty);

      // Log for manual verification
      // ignore: avoid_print
      print('\n--- Model response ---\n$response\n---');
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: false,
  );
}
