@Tags(['real-device'])
library;

import 'dart:convert';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'visual_assertion.dart';

const _deviceId = '39111FDJH00D47';
const _task = '''
  帮我通过 chrome 打开 twitter 的官网,具体步骤如下：
  1. 如果当前不在 **HOME** 页面，先通过 HOME 键进入  HOME 页面
  2. 打开chrome
  3. 在地址栏输入 twitter 的网址：https://www.x.com
  4. 点击输入法上的确认按钮
  5. 等待页面加载
  6. 确认当前页面是 twitter 的主页
''';

/// Common app name → package name mappings.
const _appMap = {
  'Chrome': 'com.android.chrome',
  'chrome': 'com.android.chrome',
  '微信': 'com.tencent.mm',
};

void main() {
  test(
    'e2e: open twitter with chrome',
    () async {
      initLogging();
      final adb = ScrcpyMcpAdb(AdbClient());

      // All device control goes through `adb shell` — no scrcpy session needed.
      // autoglm-phone emits [0,1000] normalized coordinates, so resolve the
      // device's pixel resolution once and convert each coordinate to pixels.
      final size = await _deviceSize(adb);

      Future<String> runAction(PhoneAction action) async {
        switch (action) {
          case final DoAction doAction:
            return switch (doAction.action) {
              'Tap' => _tap(adb, doAction, size),
              'Swipe' => _swipe(adb, doAction, size),
              'Type' => _typeText(adb, doAction),
              'Launch' => _launch(adb, doAction),
              'Back' => _back(adb),
              'Home' => _home(adb),
              'Long Press' => _longPress(adb, doAction, size),
              'Double Tap' => _doubleTap(adb, doAction, size),
              'Wait' => _wait(doAction),
              _ => Future.value('Unknown: ${doAction.action}'),
            };
          case final FinishAction finishAction:
            return finishAction.message;
        }
      }

      final phoneAgent = PhoneAgent(
        config: const AgentConfig(maxSteps: 10),
        llmClient: AutoglmLlmClient.fromTest(),
        takeScreenshot: () async {
          final bytes = await adb.takeScreenshot(_deviceId);
          return (base64: base64Encode(bytes), mimeType: 'image/png');
        },
        actionRunner: runAction,
      );
      final agentResult = await phoneAgent.run(_task);
      expect(agentResult, isNotNull);

      // Verify the agent actually reached the Twitter homepage.
      final check = await checkDeviceScreenContains(
        client: AutoglmLlmClient.fromTest(),
        adb: adb,
        deviceId: _deviceId,
        expectation: 'Twitter（X）的主页',
      );
      expect(check.matched, isTrue, reason: check.reason);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: false,
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Device pixel resolution from `wm size` (e.g. "Physical size: 1080x2400").
Future<(int, int)> _deviceSize(ScrcpyMcpAdb adb) async {
  final r = await adb.shell(['wm', 'size'], deviceId: _deviceId);
  final m = RegExp(r'(\d+)x(\d+)').firstMatch(r.stdout as String);
  return m != null
      ? (int.parse(m.group(1)!), int.parse(m.group(2)!))
      : (1080, 2400);
}

/// Convert an autoglm [0,1000] coordinate pair to device pixels.
(int, int) _toPx(List<int> e, (int, int) size) =>
    ((e[0] * size.$1 / 1000).round(), (e[1] * size.$2 / 1000).round());

// ── Action implementations (all via `adb shell input`) ───────────────────────

Future<String> _tap(ScrcpyMcpAdb adb, DoAction action, (int, int) size) async {
  if (action.element == null || action.element!.length < 2) {
    return 'Error: missing coordinates';
  }
  final (px, py) = _toPx(action.element!, size);
  await adb.shell(['input', 'tap', '$px', '$py'], deviceId: _deviceId);
  return 'Tapped ($px, $py)';
}

Future<String> _swipe(
  ScrcpyMcpAdb adb,
  DoAction action,
  (int, int) size,
) async {
  if (action.start == null || action.end == null) {
    return 'Error: missing coords';
  }
  final (x1, y1) = _toPx(action.start!, size);
  final (x2, y2) = _toPx(action.end!, size);
  await adb.shell(
    ['input', 'swipe', '$x1', '$y1', '$x2', '$y2', '300'],
    deviceId: _deviceId,
  );
  return 'Swiped ($x1,$y1) → ($x2,$y2)';
}

Future<String> _typeText(ScrcpyMcpAdb adb, DoAction action) async {
  if (action.text == null) return 'Error: missing text';
  // `adb shell input text` treats spaces specially (use %s) and only handles
  // ASCII; fine for the URL this test types.
  final escaped = action.text!.replaceAll(' ', '%s');
  await adb.shell(['input', 'text', escaped], deviceId: _deviceId);
  return 'Typed: ${action.text}';
}

Future<String> _launch(ScrcpyMcpAdb adb, DoAction action) async {
  if (action.app == null) return 'Error: missing app';
  final pkg = _appMap[action.app] ?? action.app!;
  final r = await adb.shell([
    'monkey',
    '-p',
    pkg,
    '-c',
    'android.intent.category.LAUNCHER',
    '1',
  ], deviceId: _deviceId);
  return r.exitCode == 0 ? 'Launched $pkg' : 'Failed: $pkg';
}

Future<String> _back(ScrcpyMcpAdb adb) async {
  await adb.shell(['input', 'keyevent', 'KEYCODE_BACK'], deviceId: _deviceId);
  return 'Pressed Back';
}

Future<String> _home(ScrcpyMcpAdb adb) async {
  await adb.shell(['input', 'keyevent', 'KEYCODE_HOME'], deviceId: _deviceId);
  return 'Pressed Home';
}

Future<String> _longPress(
  ScrcpyMcpAdb adb,
  DoAction action,
  (int, int) size,
) async {
  if (action.element == null || action.element!.length < 2) {
    return 'Error: missing coordinates';
  }
  // A long press is a zero-distance swipe held for ~800ms.
  final (px, py) = _toPx(action.element!, size);
  await adb.shell(
    ['input', 'swipe', '$px', '$py', '$px', '$py', '800'],
    deviceId: _deviceId,
  );
  return 'Long pressed ($px, $py)';
}

Future<String> _doubleTap(
  ScrcpyMcpAdb adb,
  DoAction action,
  (int, int) size,
) async {
  await _tap(adb, action, size);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await _tap(adb, action, size);
  return 'Double tapped';
}

Future<String> _wait(DoAction action) async {
  final secs = int.tryParse(
    (action.duration ?? '2s').replaceAll(RegExp('[^0-9]'), ''),
  );
  await Future<void>.delayed(Duration(seconds: secs ?? 2));
  return 'Waited ${secs ?? 2}s';
}
