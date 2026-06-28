import 'package:scrcpy_client/scrcpy_client.dart';

import 'action_runner.dart';

// Android KeyEvent constants for clearing a text field before typing.
const _keycodeHome = 3; // KEYCODE_HOME
const _keycodeA = 29; // KEYCODE_A
const _keycodeDel = 67; // KEYCODE_DEL (backspace) — deletes the selection
const _keycodeCtrlLeft = 113; // KEYCODE_CTRL_LEFT
const _metaCtrlOn = 0x1000; // META_CTRL_ON

/// Drives the device through scrcpy's control protocol over a live
/// [ScrcpySession]. Normalized model coordinates are passed straight to scrcpy
/// with a [kModelCoordSpace]×[kModelCoordSpace] frame, so scrcpy scales them to
/// the real device pixel independent of resolution. Used by the `run_task` MCP
/// tool, which already has a connected session.
///
/// `Launch` is the one action scrcpy's control protocol can't express, so this
/// strategy keeps its own [ScrcpyAdb] handle for it — a detail private to the
/// scrcpy strategy, not a dependency of the shared base.
class ScrcpyActionRunner extends PhoneActionRunner {
  ScrcpyActionRunner({
    required this.session,
    required ScrcpyAdb adb,
    required this.deviceId,
  }) : _adb = adb;

  final ScrcpySession session;
  final ScrcpyAdb _adb;
  final String deviceId;

  @override
  Future<void> tapAt(int x, int y) async {
    session.sendControlMessage(_touch(action: 0, x: x, y: y)); // down
    await Future<void>.delayed(const Duration(milliseconds: 50));
    session.sendControlMessage(_touch(action: 1, x: x, y: y)); // up
  }

  @override
  Future<void> swipeFromTo(int x1, int y1, int x2, int y2) async {
    session.sendControlMessage(
      ScrcpyInjectScrollMessage(
        x: x1,
        y: y1,
        width: kModelCoordSpace,
        height: kModelCoordSpace,
        hScroll: x2 - x1,
        vScroll: y2 - y1,
      ),
    );
  }

  @override
  Future<void> clearAndType(String text) async {
    _selectAll();
    _sendKey(_keycodeDel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    session.injectText(text);
  }

  @override
  Future<void> pressBack() async {
    session.sendControlMessage(const ScrcpyBackOrScreenOnMessage(4)); // back
  }

  @override
  Future<void> pressHome() async {
    session.sendControlMessage(
      const ScrcpyInjectKeyMessage(action: 0, keycode: _keycodeHome),
    );
  }

  @override
  Future<void> longPressAt(int x, int y) async {
    session.sendControlMessage(_touch(action: 0, x: x, y: y)); // down
    await Future<void>.delayed(const Duration(seconds: 1));
    session.sendControlMessage(_touch(action: 1, x: x, y: y)); // up
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
    return result.exitCode == 0 && !(result.stdout as String).contains('Error');
  }

  ScrcpyInjectTouchMessage _touch({
    required int action,
    required int x,
    required int y,
  }) => ScrcpyInjectTouchMessage(
    action: action,
    pointerId: 0,
    x: x,
    y: y,
    width: kModelCoordSpace,
    height: kModelCoordSpace,
  );

  /// Selects all text in the focused field via a Ctrl+A chord: Ctrl down,
  /// A down/up (with Ctrl in the metastate), Ctrl up — the way scrcpy injects
  /// modifier combinations.
  void _selectAll() {
    session.sendControlMessage(
      const ScrcpyInjectKeyMessage(action: 0, keycode: _keycodeCtrlLeft),
    );
    _sendKey(_keycodeA, metastate: _metaCtrlOn);
    session.sendControlMessage(
      const ScrcpyInjectKeyMessage(action: 1, keycode: _keycodeCtrlLeft),
    );
  }

  /// Sends a key down+up pair (optionally with modifier [metastate]).
  void _sendKey(int keycode, {int metastate = 0}) {
    session.sendControlMessage(
      ScrcpyInjectKeyMessage(action: 0, keycode: keycode, metastate: metastate),
    );
    session.sendControlMessage(
      ScrcpyInjectKeyMessage(action: 1, keycode: keycode, metastate: metastate),
    );
  }
}
