import 'dart:convert';

import 'package:scrcpy_mcp/scrcpy_mcp.dart';

/// Result of a visual assertion against a screenshot.
class ScreenCheckResult {
  const ScreenCheckResult({required this.matched, required this.reason});

  /// Whether the model judged the expectation present on screen.
  final bool matched;

  /// The model's full reply, surfaced via `expect(..., reason: r.reason)`.
  final String reason;
}

/// Parses a raw vision-model reply into a [ScreenCheckResult].
///
/// Rules: trim, take the first line. Leading "否"/"不" → not matched;
/// leading "是" → matched; anything else (including empty) → [LlmException].
/// Checking "否"/"不" before "是" avoids the `contains('是')` misjudgment
/// where "不是" was wrongly read as a match.
ScreenCheckResult parseScreenCheckResponse(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    throw const LlmException('Empty response from vision model');
  }
  final firstLine = text.split('\n').first.trim();
  if (firstLine.startsWith('否') || firstLine.startsWith('不')) {
    return ScreenCheckResult(matched: false, reason: text);
  }
  if (firstLine.startsWith('是')) {
    return ScreenCheckResult(matched: true, reason: text);
  }
  throw LlmException('Unparseable vision response: $raw');
}

const _systemPrompt =
    '你是一个手机界面分析助手。请根据截图判断用户描述的内容或状态是否出现在界面上。'
    '严格按以下格式回答：第一行只写"是"或"否"，第二行起简要说明理由。';

/// Asks [client] whether [expectation] appears in [base64Screenshot].
/// Throws [LlmException] if the reply can't be parsed.
Future<ScreenCheckResult> checkScreenContains({
  required LlmClient client,
  required String base64Screenshot,
  required String expectation,
  String mimeType = 'image/png',
}) async {
  final response = await client.chat(
    messages: [
      const LlmMessage(role: 'system', textContent: _systemPrompt),
      LlmMessage(
        role: 'user',
        textContent: '界面上是否出现了"$expectation"？',
        imageBase64: base64Screenshot,
        imageMimeType: mimeType,
      ),
    ],
  );
  return parseScreenCheckResponse(response.text ?? '');
}

/// Captures a screenshot from [deviceId] via [adb], then runs
/// [checkScreenContains].
Future<ScreenCheckResult> checkDeviceScreenContains({
  required LlmClient client,
  required ScrcpyMcpAdb adb,
  required String deviceId,
  required String expectation,
}) async {
  final bytes = await adb.takeScreenshot(deviceId);
  return checkScreenContains(
    client: client,
    base64Screenshot: base64Encode(bytes),
    expectation: expectation,
  );
}
