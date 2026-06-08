/// Standalone calibration: compares model-reported coordinates against
/// uiautomator ground truth.
///
/// Run:
///   dart test test/phone_agent_eval/coordinate_calibration_test.dart
@TestOn('vm')
@Tags(['real-device'])
library;

import 'dart:convert';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

final _log = Logger('coord_cal');

/// Parsed element from uiautomator dump.
typedef _UiElement = ({
  String text,
  int cx,
  int cy,
  int x1,
  int y1,
  int x2,
  int y2,
});

void main() {
  initLogging();

  test(
    'coordinate calibration',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final adb = ScrcpyMcpAdb(AdbClient());
      final devices = await adb.getDevices();
      if (devices.isEmpty) {
        markTestSkipped('No device');
        return;
      }
      final deviceId = devices.first;

      // ── 1. Open Settings (stable, predictable UI) ──
      await adb.shell([
        'am',
        'start',
        '-a',
        'android.settings.SETTINGS',
      ], deviceId: deviceId);
      await Future<void>.delayed(const Duration(seconds: 2));

      // ── 2. uiautomator ground truth ──
      await adb.shell([
        'uiautomator',
        'dump',
        '/sdcard/calib_ui.xml',
      ], deviceId: deviceId);
      // Pull the dump (adb pull via shell is messy; use file read)
      final dumpResult = await adb.shell([
        'cat',
        '/sdcard/calib_ui.xml',
      ], deviceId: deviceId);
      final xml = (dumpResult.stdout as String).trim();
      final groundTruth = _parseElements(xml);
      _log.info('uiautomator found ${groundTruth.length} labeled elements');

      // ── 3. Take screenshot ──
      final screenshot = await adb.takeScreenshot(deviceId);
      final chat = AutoGLMClient.fromTest().chat;

      // ── 4. Ask model for each element's center ──
      final results = <Map<String, Object?>>[];
      for (final element in groundTruth) {
        final prompt =
            '''
截图中有一个文字为"${element.text}"的UI元素。
请用 do(action="Tap", element=[x,y]) 返回你认为它的中心坐标（在[0,1000]坐标空间）。
只返回单独一行 do(...) 指令，不要附带其他内容。''';

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
        final deviationX = modelCoord != null
            ? (modelCoord.x - element.cx).abs()
            : -1;
        final deviationY = modelCoord != null
            ? (modelCoord.y - element.cy).abs()
            : -1;

        results.add({
          'element': element.text,
          'actual_bounds':
              '[${element.x1},${element.y1}][${element.x2},${element.y2}]',
          'actual_center_px': '(${element.cx}, ${element.cy})',
          'actual_center_model':
              '(${_toModelX(element.cx)}, ${_toModelY(element.cy)})',
          'model_raw': response.text,
          'model_coord': modelCoord != null
              ? '(${modelCoord.x}, ${modelCoord.y})'
              : '(parse error)',
          'deviation_px': '($deviationX, $deviationY)',
        });

        _log.info(
          '${element.text}: actual=(${element.cx},${element.cy}) '
          'model=$modelCoord → Δ=($deviationX, $deviationY)px',
        );
      }

      // ── 5. Print summary table ──
      _log.info('');
      _log.info('═══════════════════════════════════════════════════');
      _log.info('  COORDINATE CALIBRATION RESULTS');
      _log.info('═══════════════════════════════════════════════════');
      for (final r in results) {
        _log.info(
          '  ${r['element']}: actual_center=${r['actual_center_px']} '
          'model=${r['model_coord']} Δ=${r['deviation_px']}',
        );
      }
      _log.info('═══════════════════════════════════════════════════');

      // Clean up
      await adb.shell(['rm', '/sdcard/calib_ui.xml'], deviceId: deviceId);
    },
  );
}

int _toModelX(int px) => (px * 1000 / 1080).round();
int _toModelY(int py) => (py * 1000 / 2340).round();

/// Parse clickable elements with text from uiautomator XML using regex.
List<_UiElement> _parseElements(String xml) {
  final elements = <_UiElement>[];
  final seen = <String>{};
  // Match each <node .../> with text and bounds
  final nodeRe = RegExp(
    r'<node[^>]*\stext="([^"]+)"[^>]*\sclickable="true"[^>]*\sbounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*/?>',
  );

  for (final m in nodeRe.allMatches(xml)) {
    final text = m.group(1)!;
    final x1 = int.parse(m.group(2)!);
    final y1 = int.parse(m.group(3)!);
    final x2 = int.parse(m.group(4)!);
    final y2 = int.parse(m.group(5)!);
    final cx = (x1 + x2) ~/ 2;
    final cy = (y1 + y2) ~/ 2;

    if (seen.add(text)) {
      elements.add((
        text: text,
        cx: cx,
        cy: cy,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
      ));
    }
  }

  return elements;
}

/// Parse "do(action="Tap", element=[x,y])" → (x,y) or null.
({int x, int y})? _parseTapCoord(String raw) {
  final m = RegExp(r'element\s*=\s*\[(\d+)\s*,\s*(\d+)\]').firstMatch(raw);
  if (m == null) return null;
  return (x: int.parse(m.group(1)!), y: int.parse(m.group(2)!));
}
