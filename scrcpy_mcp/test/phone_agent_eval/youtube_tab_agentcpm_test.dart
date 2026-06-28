/// AgentCPM-GUI variant: model coordinate accuracy for YouTube's "我" tab.
///
/// Requires MODEL_SCOPE_API_KEY env var.
///
/// Run:
///   MODEL_SCOPE_API_KEY=your-key dart test test/phone_agent_eval/youtube_tab_agentcpm_test.dart
@TestOn('vm')
@Tags(['real-device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

final _log = Logger('yt_agentcpm');

void main() {
  initLogging();

  test(
    'YouTube "我" tab — AgentCPM-GUI',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['MODEL_SCOPE_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        markTestSkipped('Set MODEL_SCOPE_API_KEY env var.');
        return;
      }

      final adb = ScrcpyMcpAdb(AdbClient());
      final devices = await adb.getDevices();
      if (devices.isEmpty) {
        markTestSkipped('No device');
        return;
      }
      final deviceId = devices.first;

      // ── 1. Open YouTube ──
      await adb.shell([
        'am',
        'force-stop',
        'com.google.android.youtube',
      ], deviceId: deviceId);
      await adb.shell([
        'am',
        'force-stop',
        'com.android.chrome',
      ], deviceId: deviceId);
      await adb.shell([
        'am',
        'start',
        '-n',
        'com.google.android.youtube/com.google.android.apps.youtube.app.WatchWhileActivity',
      ], deviceId: deviceId);
      await Future<void>.delayed(const Duration(seconds: 3));

      // Dismiss dialogs
      for (var attempt = 0; attempt < 3; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        await adb.shell([
          'uiautomator',
          'dump',
          '/sdcard/yt_pre.xml',
        ], deviceId: deviceId);
        final pre =
            (await adb.shell([
                  'cat',
                  '/sdcard/yt_pre.xml',
                ], deviceId: deviceId)).stdout
                as String;
        if (pre.contains('text="我"') &&
            pre.contains('com.google.android.youtube')) {
          break;
        }
        _log.info('Dismissing dialog (attempt ${attempt + 1})...');
        await adb.shell([
          'input',
          'keyevent',
          'KEYCODE_BACK',
        ], deviceId: deviceId);
      }
      await adb.shell(['rm', '/sdcard/yt_pre.xml'], deviceId: deviceId);

      // ── 2. uiautomator ground truth ──
      await adb.shell([
        'uiautomator',
        'dump',
        '/sdcard/yt_tab_ui.xml',
      ], deviceId: deviceId);
      final dumpResult = await adb.shell([
        'cat',
        '/sdcard/yt_tab_ui.xml',
      ], deviceId: deviceId);
      final xml = (dumpResult.stdout as String).trim();
      final wo = _parseTextElements(xml).where((e) => e.text == '我').toList();
      _log.info(
        'Ground truth "我": ${wo.map((e) => '[${e.x1},${e.y1}][${e.x2},${e.y2}] center=(${e.cx},${e.cy})').join(', ')}',
      );

      // ── 3. Take screenshot, ask AgentCPM-GUI ──
      final screenshot = await adb.takeScreenshot(deviceId);
      final chat = AgentCPMGuiClient(
        baseUrl: 'https://api-inference.modelscope.cn/v1',
        apiKey: apiKey,
        model: 'OpenBMB/AgentCPM-GUI',
      ).chat;

      const prompt = '请点击屏幕底部导航栏最右边的"我"标签按钮。';

      final response = await chat(
        messages: [
          LlmMessage(
            role: 'user',
            textContent: prompt,
            imageBase64: base64Encode(screenshot),
            imageMimeType: 'image/png',
          ),
        ],
      );

      final modelCoord = _parseTapCoord(response.text ?? '');
      _log.info('Raw response: ${response.text}');
      _log.info('Model coord: $modelCoord');

      // ── 4. Execute tap ──
      if (modelCoord == null) {
        fail('AgentCPM-GUI did not return a parseable coordinate.');
      }

      final screenSize = await _getScreenSize(adb, deviceId);
      final tapX = _toPx(modelCoord.x, screenSize.$1);
      final tapY = _toPx(modelCoord.y, screenSize.$2);

      await adb.shell(['input', 'tap', '$tapX', '$tapY'], deviceId: deviceId);
      await Future<void>.delayed(const Duration(seconds: 2));

      final postTap = await adb.takeScreenshot(deviceId);
      await File('/tmp/yt_agentcpm_post_tap.png').writeAsBytes(postTap);

      // ── 5. Compare ──
      _log.info('');
      _log.info('═══════════════════════════════════════════════════');
      _log.info('  AgentCPM-GUI vs AutoGLM on YouTube "我" tab');
      _log.info('═══════════════════════════════════════════════════');
      for (final e in wo) {
        final dx = (tapX - e.cx).abs();
        final dy = (tapY - e.cy).abs();
        final hitX = tapX >= e.x1 && tapX <= e.x2;
        final hitY = tapY >= e.y1 && tapY <= e.y2;
        _log.info('  Ground truth:  (${e.cx}, ${e.cy})px');
        _log.info('  AgentCPM-GUI:  ($tapX, $tapY)px  Δ=($dx,$dy)px');
        _log.info(
          '  Hit? X=$hitX Y=$hitY → ${hitX && hitY ? "✅ HIT" : "❌ MISS"}',
        );
        _log.info('    (AutoGLM was: Y MISS by 49px)');
      }
      _log.info('═══════════════════════════════════════════════════');

      await adb.shell(['rm', '/sdcard/yt_tab_ui.xml'], deviceId: deviceId);
    },
  );
}

Future<(int, int)> _getScreenSize(ScrcpyMcpAdb adb, String deviceId) async {
  final result = await adb.shell(['wm', 'size'], deviceId: deviceId);
  final m = RegExp(r'(\d+)x(\d+)').firstMatch((result.stdout as String).trim());
  if (m == null) return (1080, 2340);
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

int _toPx(int model, int screenSize) => (model * screenSize / 1000).round();

typedef _TextElement = ({
  String text,
  int x1,
  int y1,
  int x2,
  int y2,
  int cx,
  int cy,
});

List<_TextElement> _parseTextElements(String xml) {
  final elements = <_TextElement>[];
  final nodeRe = RegExp(
    r'<node[^>]*\stext="([^"]*)"[^>]*\sbounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*/?>',
  );
  for (final m in nodeRe.allMatches(xml)) {
    final text = m.group(1)!;
    final x1 = int.parse(m.group(2)!);
    final y1 = int.parse(m.group(3)!);
    final x2 = int.parse(m.group(4)!);
    final y2 = int.parse(m.group(5)!);
    elements.add((
      text: text,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      cx: (x1 + x2) ~/ 2,
      cy: (y1 + y2) ~/ 2,
    ));
  }
  return elements;
}

({int x, int y})? _parseTapCoord(String raw) {
  final m = RegExp(r'element\s*=\s*\[(\d+)\s*,\s*(\d+)\]').firstMatch(raw);
  if (m == null) return null;
  return (x: int.parse(m.group(1)!), y: int.parse(m.group(2)!));
}
