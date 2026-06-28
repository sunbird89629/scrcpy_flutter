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

      // ── 0. Get screen size ──
      final sizeResult = await adb.shell(['wm', 'size'], deviceId: deviceId);
      final sizeMatch = RegExp(
        r'(\d+)x(\d+)',
      ).firstMatch((sizeResult.stdout as String).trim());
      final screenWidth = int.parse(sizeMatch!.group(1)!);
      final screenHeight = int.parse(sizeMatch.group(2)!);
      _log.info('Screen: ${screenWidth}x$screenHeight');

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
      final dumpResult = await adb.shell([
        'cat',
        '/sdcard/calib_ui.xml',
      ], deviceId: deviceId);
      final xml = (dumpResult.stdout as String).trim();
      final groundTruth = _parseElements(xml, screenWidth, screenHeight);
      _log.info('uiautomator found ${groundTruth.length} labeled elements');

      // ── 3. Take screenshot ──
      final screenshot = await adb.takeScreenshot(deviceId);
      final chat = AutoGLMOfficialClient.fromTest().chat;

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
        // Convert model [0,1000] → pixel space before comparing
        final modelPxX = modelCoord != null
            ? _toPx(modelCoord.x, screenWidth)
            : -1;
        final modelPxY = modelCoord != null
            ? _toPx(modelCoord.y, screenHeight)
            : -1;
        final deviationX = modelCoord != null
            ? (modelPxX - element.cx).abs()
            : -1;
        final deviationY = modelCoord != null
            ? (modelPxY - element.cy).abs()
            : -1;

        results.add({
          'element': element.text,
          'actual_bounds':
              '[${element.x1},${element.y1}][${element.x2},${element.y2}]',
          'actual_center_px': '(${element.cx}, ${element.cy})',
          'actual_center_model':
              '(${_toModel(element.cx, screenWidth)}, ${_toModel(element.cy, screenHeight)})',
          'model_raw': response.text,
          'model_coord': modelCoord != null
              ? '(${modelCoord.x}, ${modelCoord.y})'
              : '(parse error)',
          'model_px': '($modelPxX, $modelPxY)',
          'deviation_px': '($deviationX, $deviationY)',
        });

        _log.info(
          '${element.text}: actual=(${element.cx},${element.cy})px '
          'model=($modelPxX,$modelPxY)px → Δ=($deviationX,$deviationY)px',
        );
      }

      // ── 5. Print summary table ──
      final allX = results.where((r) => r['deviation_px'] != '(-1, -1)').map((
        r,
      ) {
        final parts = (r['deviation_px']! as String)
            .replaceAll(RegExp('[()]'), '')
            .split(', ');
        return (dx: int.parse(parts[0]), dy: int.parse(parts[1]));
      }).toList();

      _log.info('');
      _log.info('═══════════════════════════════════════════════════');
      _log.info('  COORDINATE CALIBRATION RESULTS');
      _log.info('  Screen: ${screenWidth}x$screenHeight');
      _log.info('═══════════════════════════════════════════════════');
      for (final r in results) {
        _log.info(
          '  ${r['element']}: actual=${r['actual_center_px']} '
          'model=${r['model_px']} Δ=${r['deviation_px']}',
        );
      }
      if (allX.isNotEmpty) {
        final avgDx =
            (allX.map((e) => e.dx).reduce((a, b) => a + b) / allX.length)
                .round();
        final avgDy =
            (allX.map((e) => e.dy).reduce((a, b) => a + b) / allX.length)
                .round();
        _log.info('─────────────────────────────────────────────────');
        _log.info('  Average deviation: X=${avgDx}px, Y=${avgDy}px');
        _log.info(
          '  (model → pixel: X*$screenWidth/1000, Y*$screenHeight/1000)',
        );
      }
      _log.info('═══════════════════════════════════════════════════');

      // Clean up
      await adb.shell(['rm', '/sdcard/calib_ui.xml'], deviceId: deviceId);
    },
  );
}

/// Convert model [0,1000] → pixel coordinate.
int _toPx(int model, int screenSize) => (model * screenSize / 1000).round();

/// Convert pixel → model [0,1000].
int _toModel(int px, int screenSize) => (px * 1000 / screenSize).round();

/// Parse elements with text from uiautomator XML.
/// Uses the text node's own bounds (narrower than the clickable row).
/// Model estimates the ROW center, so X deviation reflects text width, not error.
List<_UiElement> _parseElements(String xml, int screenW, int screenH) {
  final elements = <_UiElement>[];
  final seen = <String>{};
  final nodeRe = RegExp(
    r'<node[^>]*\stext="([^"]+)"[^>]*\sbounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*/?>',
  );

  for (final m in nodeRe.allMatches(xml)) {
    final text = m.group(1)!;
    if (text.length > 30) continue;
    final x1 = int.parse(m.group(2)!);
    final y1 = int.parse(m.group(3)!);
    final x2 = int.parse(m.group(4)!);
    final y2 = int.parse(m.group(5)!);

    if (x1 == 0 && y1 == 0 && x2 == screenW && y2 == screenH) continue;

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
