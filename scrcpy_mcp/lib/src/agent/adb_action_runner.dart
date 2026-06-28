import 'package:scrcpy_client/scrcpy_client.dart';

import 'action_runner.dart';

/// Drives the device entirely through `adb shell input` — no scrcpy session
/// needed. Normalized model coordinates are converted to device pixels using
/// [size] (the device's `wm size` resolution). Used by real-device e2e tests
/// that exercise the agent without standing up a mirroring session.
class AdbActionRunner extends PhoneActionRunner {
  AdbActionRunner({
    required ScrcpyAdb adb,
    required this.deviceId,
    required this.size,
  }) : _adb = adb;

  final ScrcpyAdb _adb;
  final String deviceId;

  /// Device pixel resolution `(width, height)`.
  final (int, int) size;

  /// Convert a normalized [kModelCoordSpace] coordinate pair to device pixels.
  (int, int) _toPx(int x, int y) => (
    (x * size.$1 / kModelCoordSpace).round(),
    (y * size.$2 / kModelCoordSpace).round(),
  );

  @override
  Future<void> tapAt(int x, int y) async {
    final (px, py) = _toPx(x, y);
    await _adb.shell(['input', 'tap', '$px', '$py'], deviceId: deviceId);
  }

  @override
  Future<void> swipeFromTo(int x1, int y1, int x2, int y2) async {
    final (px1, py1) = _toPx(x1, y1);
    final (px2, py2) = _toPx(x2, y2);
    await _adb.shell([
      'input',
      'swipe',
      '$px1',
      '$py1',
      '$px2',
      '$py2',
      '300',
    ], deviceId: deviceId);
  }

  @override
  Future<void> clearAndType(String text) async {
    // Clear the field first (select-all + delete). NB: `input keyevent
    // KEYCODE_CTRL_A` is a no-op (not a real keycode); the chord must go through
    // `input keycombination`.
    await _adb.shell([
      'input',
      'keycombination',
      'KEYCODE_CTRL_LEFT',
      'KEYCODE_A',
    ], deviceId: deviceId);
    await _adb.shell(['input', 'keyevent', 'KEYCODE_DEL'], deviceId: deviceId);
    // `adb shell input text` treats spaces specially (use %s) and only handles
    // ASCII; non-ASCII text would need an IME like ADBKeyboard.
    final escaped = text.replaceAll(' ', '%s');
    await _adb.shell(['input', 'text', escaped], deviceId: deviceId);
  }

  @override
  Future<void> pressBack() async {
    await _adb.shell(['input', 'keyevent', 'KEYCODE_BACK'], deviceId: deviceId);
  }

  @override
  Future<void> pressHome() async {
    await _adb.shell(['input', 'keyevent', 'KEYCODE_HOME'], deviceId: deviceId);
  }

  @override
  Future<void> longPressAt(int x, int y) async {
    // A long press is a zero-distance swipe held for ~800ms.
    final (px, py) = _toPx(x, y);
    await _adb.shell([
      'input',
      'swipe',
      '$px',
      '$py',
      '$px',
      '$py',
      '800',
    ], deviceId: deviceId);
  }

  @override
  Future<bool> launchPackage(String pkg) async {
    final result = await _adb.shell([
      'monkey',
      '-p',
      pkg,
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ], deviceId: deviceId);
    return result.exitCode == 0;
  }
}
