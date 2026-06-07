// Shared adb-driven action runner for real-device agent e2e tests.
//
// This is a plain library (not a *_test.dart), so `dart test` skips it. Import
// it from real-device test files to run an autoglm-phone task with one call.
//
// All device control goes through `adb shell input` — no scrcpy session needed.
// autoglm-phone emits [0,1000] normalized coordinates, so we resolve the
// device's pixel resolution once (`wm size`) and convert each coordinate.

import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

const _appMap = {
  'Chrome': 'com.android.chrome',
  'chrome': 'com.android.chrome',
  'YouTube': 'com.google.android.youtube',
  'youtube': 'com.google.android.youtube',
  '微信': 'com.tencent.mm',
};

/// Runs [task] on a real device via autoglm-phone, driving the device entirely
/// through `adb shell`. If [deviceId] is null, the first connected device is
/// used. Returns the agent's [AgentResult].
Future<AgentResult> runAgentTask({
  required AdbClient adb,
  required String task,
  required String deviceId,
  int maxSteps = 15,
}) async {
  final device = deviceId;
  final (screenWidth, screenHeight) = await adb.getDeviceScreenInfo(device);
  final agent = PhoneAgent(
    config: AgentConfig(maxSteps: maxSteps),
    llmClient: AutoglmLlmClient.fromTest(),
    takeScreenshot: blankRetryingScreenshot(() => adb.takeScreenshot(device)),
    actionRunner: (action) => _runAction(ScrcpyMcpAdb(adb), device, (
      screenWidth.toInt(),
      screenHeight.toInt(),
    ), action),
  );
  return agent.run(task);
}

/// Device pixel resolution from `wm size` (e.g. "Physical size: 1080x2400").
// Future<(int, int)> _deviceSize(ScrcpyMcpAdb adb, String deviceId) async {
//   final r = await adb.shell(['wm', 'size'], deviceId: deviceId);
//   final m = RegExp(r'(\d+)x(\d+)').firstMatch(r.stdout as String);
//   return m != null
//       ? (int.parse(m.group(1)!), int.parse(m.group(2)!))
//       : (1080, 2400);
// }

/// Convert an autoglm [0,1000] coordinate pair to device pixels.
(int, int) _toPx(List<int> e, (int, int) size) =>
    ((e[0] * size.$1 / 1000).round(), (e[1] * size.$2 / 1000).round());

Future<String> _runAction(
  ScrcpyMcpAdb adb,
  String deviceId,
  (int, int) size,
  PhoneAction action,
) async {
  switch (action) {
    case final DoAction d:
      return switch (d.action) {
        'Tap' => _tap(adb, deviceId, size, d),
        'Swipe' => _swipe(adb, deviceId, size, d),
        'Type' || 'Type_Name' => _typeText(adb, deviceId, d),
        'Launch' => _launch(adb, deviceId, d),
        'Back' => _back(adb, deviceId),
        'Home' => _home(adb, deviceId),
        'Long Press' => _longPress(adb, deviceId, size, d),
        'Double Tap' => _doubleTap(adb, deviceId, size, d),
        'Wait' => _wait(d),
        'Note' => Future.value('Noted page content'),
        'Take_over' => Future.value(
          'Manual intervention requested: ${d.message ?? "no details"}',
        ),
        _ => Future.value('Unknown: ${d.action}'),
      };
    case final FinishAction f:
      return f.message;
  }
}

// ── Action implementations (all via `adb shell input`) ───────────────────────

Future<String> _tap(
  ScrcpyMcpAdb adb,
  String deviceId,
  (int, int) size,
  DoAction action,
) async {
  if (action.element == null || action.element!.length < 2) {
    return 'Error: missing coordinates';
  }
  final (px, py) = _toPx(action.element!, size);
  await adb.shell(['input', 'tap', '$px', '$py'], deviceId: deviceId);
  return 'Tapped ($px, $py)';
}

Future<String> _swipe(
  ScrcpyMcpAdb adb,
  String deviceId,
  (int, int) size,
  DoAction action,
) async {
  if (action.start == null || action.end == null) {
    return 'Error: missing coords';
  }
  final (x1, y1) = _toPx(action.start!, size);
  final (x2, y2) = _toPx(action.end!, size);
  await adb.shell([
    'input',
    'swipe',
    '$x1',
    '$y1',
    '$x2',
    '$y2',
    '300',
  ], deviceId: deviceId);
  return 'Swiped ($x1,$y1) → ($x2,$y2)';
}

Future<String> _typeText(
  ScrcpyMcpAdb adb,
  String deviceId,
  DoAction action,
) async {
  if (action.text == null) return 'Error: missing text';
  // Type replaces the field, so clear it first (select-all + delete). NB:
  // `input keyevent KEYCODE_CTRL_A` is a no-op (not a real keycode); the chord
  // must go through `input keycombination`.
  await adb.shell([
    'input',
    'keycombination',
    'KEYCODE_CTRL_LEFT',
    'KEYCODE_A',
  ], deviceId: deviceId);
  await adb.shell(['input', 'keyevent', 'KEYCODE_DEL'], deviceId: deviceId);
  // `adb shell input text` treats spaces specially (use %s) and only handles
  // ASCII; non-ASCII text would need an IME like ADBKeyboard.
  final escaped = action.text!.replaceAll(' ', '%s');
  await adb.shell(['input', 'text', escaped], deviceId: deviceId);
  return 'Typed: ${action.text}';
}

Future<String> _launch(
  ScrcpyMcpAdb adb,
  String deviceId,
  DoAction action,
) async {
  if (action.app == null) return 'Error: missing app';
  final pkg = _appMap[action.app] ?? action.app!;
  final r = await adb.shell([
    'monkey',
    '-p',
    pkg,
    '-c',
    'android.intent.category.LAUNCHER',
    '1',
  ], deviceId: deviceId);
  return r.exitCode == 0 ? 'Launched $pkg' : 'Failed: $pkg';
}

Future<String> _back(ScrcpyMcpAdb adb, String deviceId) async {
  await adb.shell(['input', 'keyevent', 'KEYCODE_BACK'], deviceId: deviceId);
  return 'Pressed Back';
}

Future<String> _home(ScrcpyMcpAdb adb, String deviceId) async {
  await adb.shell(['input', 'keyevent', 'KEYCODE_HOME'], deviceId: deviceId);
  return 'Pressed Home';
}

Future<String> _longPress(
  ScrcpyMcpAdb adb,
  String deviceId,
  (int, int) size,
  DoAction action,
) async {
  if (action.element == null || action.element!.length < 2) {
    return 'Error: missing coordinates';
  }
  // A long press is a zero-distance swipe held for ~800ms.
  final (px, py) = _toPx(action.element!, size);
  await adb.shell([
    'input',
    'swipe',
    '$px',
    '$py',
    '$px',
    '$py',
    '800',
  ], deviceId: deviceId);
  return 'Long pressed ($px, $py)';
}

Future<String> _doubleTap(
  ScrcpyMcpAdb adb,
  String deviceId,
  (int, int) size,
  DoAction action,
) async {
  await _tap(adb, deviceId, size, action);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await _tap(adb, deviceId, size, action);
  return 'Double tapped';
}

Future<String> _wait(DoAction action) async {
  final secs = int.tryParse(
    (action.duration ?? '2s').replaceAll(RegExp('[^0-9]'), ''),
  );
  await Future<void>.delayed(Duration(seconds: secs ?? 2));
  return 'Waited ${secs ?? 2}s';
}
