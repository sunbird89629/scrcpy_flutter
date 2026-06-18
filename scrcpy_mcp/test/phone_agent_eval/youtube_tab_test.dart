/// Focused diagnostic: how accurately can the model locate YouTube's "我" tab?
///
/// Run:
///   dart test test/phone_agent_eval/youtube_tab_test.dart
@TestOn('vm')
@Tags(['real-device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

final _log = Logger('youtube_tab');

void main() {
  initLogging();

  test(
    'YouTube "我" tab tap accuracy',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final adb = ScrcpyMcpAdb(AdbClient());
      final devices = await adb.getDevices();
      if (devices.isEmpty) {
        markTestSkipped('No device');
        return;
      }
      final deviceId = devices.first;

      // ── 1. Open YouTube, dismiss any dialogs ──
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

      // Dismiss first-launch dialogs (notification permission etc.)
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

      // ── 2. uiautomator ground truth for "我" tab ──
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

      // Find all text nodes, look for "我"
      final uiElements = _parseTextElements(xml);
      final wo = uiElements.where((e) => e.text == '我').toList();
      _log.info('Found ${wo.length} element(s) with text "我":');
      for (final e in wo) {
        _log.info(
          '  bounds=[${e.x1},${e.y1}][${e.x2},${e.y2}] '
          'center=(${e.cx},${e.cy})px',
        );
      }

      // ── 3. Take screenshot, ask model ──
      final screenshot = await adb.takeScreenshot(deviceId);
      final chat = AutoGLMOfficialClient.fromTest().chat;

      final prompt = [
        '截图中是 YouTube 应用的首页。',
        '底部导航栏最右边有一个"我"标签按钮。',
        '请用 do(action="Tap", element=[x,y]) 返回你认为"我"标签的中心坐标（[0,1000]坐标空间）。',
        '只返回单独一行 do(...) 指令。',
      ].join('\n');

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
      _log.info('Model response: ${response.text}');
      _log.info('Model coord: $modelCoord');

      // ── 4. Execute the tap and verify ──
      if (modelCoord == null) {
        fail('Model did not return a parseable coordinate.');
      }

      final screenSize = await _getScreenSize(adb, deviceId);
      final tapX = _toPx(modelCoord.x, screenSize.$1);
      final tapY = _toPx(modelCoord.y, screenSize.$2);
      _log.info('Tapping at pixel ($tapX, $tapY)...');

      await adb.shell(['input', 'tap', '$tapX', '$tapY'], deviceId: deviceId);
      await Future<void>.delayed(const Duration(seconds: 2));

      // Take post-tap screenshot
      final postTap = await adb.takeScreenshot(deviceId);
      await File('/tmp/yt_tab_post_tap.png').writeAsBytes(postTap);
      _log.info('Post-tap screenshot saved to /tmp/yt_tab_post_tap.png');

      // ── 5. Compare with ground truth ──
      _log.info('');
      _log.info('═══════════════════════════════════════════════════');
      _log.info('  YouTube "我" TAB ACCURACY');
      _log.info('═══════════════════════════════════════════════════');
      for (final e in wo) {
        final dx = (tapX - e.cx).abs();
        final dy = (tapY - e.cy).abs();
        _log.info('  Ground truth center: (${e.cx}, ${e.cy})px');
        _log.info('  Model tap:           ($tapX, $tapY)px');
        _log.info('  Deviation:           ($dx, $dy)px');
        _log.info(
          '  Model coordinate:    (${modelCoord.x}, ${modelCoord.y}) → ($tapX, $tapY)px',
        );

        // Determine if tap would hit the element
        final hit =
            tapX >= e.x1 && tapX <= e.x2 && tapY >= e.y1 && tapY <= e.y2;
        final hitX = tapX >= e.x1 && tapX <= e.x2;
        final hitY = tapY >= e.y1 && tapY <= e.y2;
        _log.info(
          '  Hit? X: $hitX (target: ${e.x1}-${e.x2}), '
          'Y: $hitY (target: ${e.y1}-${e.y2}) → ${hit ? "✅ HIT" : "❌ MISS"}',
        );
      }
      _log.info('═══════════════════════════════════════════════════');

      // Clean up
      await adb.shell(['rm', '/sdcard/yt_tab_ui.xml'], deviceId: deviceId);
    },
  );
}

/// Get screen resolution.
Future<(int, int)> _getScreenSize(ScrcpyMcpAdb adb, String deviceId) async {
  final result = await adb.shell(['wm', 'size'], deviceId: deviceId);
  final m = RegExp(r'(\d+)x(\d+)').firstMatch((result.stdout as String).trim());
  if (m == null) return (1080, 2340);
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

/// Convert model [0,1000] → pixel.
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

/// Parse all nodes with text from uiautomator XML.
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

/// Parse "do(action="Tap", element=[x,y])" → (x,y) or null.
({int x, int y})? _parseTapCoord(String raw) {
  final m = RegExp(r'element\s*=\s*\[(\d+)\s*,\s*(\d+)\]').firstMatch(raw);
  if (m == null) return null;
  return (x: int.parse(m.group(1)!), y: int.parse(m.group(2)!));
}
