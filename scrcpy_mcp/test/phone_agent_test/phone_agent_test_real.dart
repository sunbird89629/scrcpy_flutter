import 'dart:convert';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

const _deviceId = '39111FDJH00D47';
const _task = '帮我通过 chrome 打开 twitter 的官网';

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

      // Create and connect a real scrcpy session for sending control messages.
      final session = await ScrcpySessionImpl.create(adb: adb);
      await session.start(_deviceId);

      try {
        Future<(int, int)> screenSize() async {
          if (session.videoWidth != null && session.videoHeight != null) {
            return (session.videoWidth!, session.videoHeight!);
          }
          final r = await adb.shell(['wm', 'size'], deviceId: _deviceId);
          final m = RegExp(r'(\d+)x(\d+)').firstMatch(r.stdout as String);
          return m != null
              ? (int.parse(m.group(1)!), int.parse(m.group(2)!))
              : (1080, 1920);
        }

        Future<String> runAction(PhoneAction action) async {
          switch (action) {
            case final DoAction doAction:
              return switch (doAction.action) {
                'Tap' => _tap(session, doAction, screenSize),
                'Swipe' => _swipe(session, doAction, screenSize),
                'Type' => _typeText(session, doAction),
                'Launch' => _launch(adb, doAction),
                'Back' => _back(session),
                'Home' => _home(session),
                'Long Press' => _longPress(session, doAction, screenSize),
                'Double Tap' => _doubleTap(session, doAction, screenSize),
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
      } finally {
        await session.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: false,
  );
}

// ── Action implementations ─────────────────────────────────────────────────

Future<String> _tap(
  ScrcpySession session,
  DoAction action,
  Future<(int, int)> Function() size,
) async {
  if (action.element == null || action.element!.length < 2) {
    return 'Error: missing coordinates';
  }
  final s = await size();
  session.sendControlMessage(ScrcpyInjectTouchMessage(
    action: 0, pointerId: 0,
    x: action.element![0], y: action.element![1],
    width: s.$1, height: s.$2,
  ));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  session.sendControlMessage(ScrcpyInjectTouchMessage(
    action: 1, pointerId: 0,
    x: action.element![0], y: action.element![1],
    width: s.$1, height: s.$2,
  ));
  return 'Tapped (${action.element![0]}, ${action.element![1]})';
}

Future<String> _swipe(
  ScrcpySession session,
  DoAction action,
  Future<(int, int)> Function() size,
) async {
  if (action.start == null || action.end == null) return 'Error: missing coords';
  final s = await size();
  session.sendControlMessage(ScrcpyInjectScrollMessage(
    x: action.start![0], y: action.start![1],
    width: s.$1, height: s.$2,
    hScroll: action.end![0] - action.start![0],
    vScroll: action.end![1] - action.start![1],
  ));
  return 'Swiped (${action.start![0]},${action.start![1]}) → (${action.end![0]},${action.end![1]})';
}

Future<String> _typeText(ScrcpySession session, DoAction action) async {
  if (action.text == null) return 'Error: missing text';
  session.injectText(action.text!);
  return 'Typed: ${action.text}';
}

Future<String> _launch(ScrcpyMcpAdb adb, DoAction action) async {
  if (action.app == null) return 'Error: missing app';
  final pkg = _appMap[action.app] ?? action.app!;
  final r = await adb.shell(
    ['monkey', '-p', pkg, '-c', 'android.intent.category.LAUNCHER', '1'],
    deviceId: _deviceId,
  );
  return r.exitCode == 0 ? 'Launched $pkg' : 'Failed: $pkg';
}

Future<String> _back(ScrcpySession session) async {
  session.sendControlMessage(const ScrcpyBackOrScreenOnMessage(4));
  return 'Pressed Back';
}

Future<String> _home(ScrcpySession session) async {
  session.sendControlMessage(const ScrcpyInjectKeyMessage(action: 0, keycode: 3));
  return 'Pressed Home';
}

Future<String> _longPress(
  ScrcpySession session,
  DoAction action,
  Future<(int, int)> Function() size,
) async {
  if (action.element == null || action.element!.length < 2) {
    return 'Error: missing coordinates';
  }
  final s = await size();
  session.sendControlMessage(ScrcpyInjectTouchMessage(
    action: 0, pointerId: 0,
    x: action.element![0], y: action.element![1],
    width: s.$1, height: s.$2,
  ));
  await Future<void>.delayed(const Duration(seconds: 1));
  session.sendControlMessage(ScrcpyInjectTouchMessage(
    action: 1, pointerId: 0,
    x: action.element![0], y: action.element![1],
    width: s.$1, height: s.$2,
  ));
  return 'Long pressed (${action.element![0]}, ${action.element![1]})';
}

Future<String> _doubleTap(
  ScrcpySession session,
  DoAction action,
  Future<(int, int)> Function() size,
) async {
  await _tap(session, action, size);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await _tap(session, action, size);
  return 'Double tapped';
}

Future<String> _wait(DoAction action) async {
  final secs = int.tryParse(
    (action.duration ?? '2s').replaceAll(RegExp('[^0-9]'), ''),
  );
  await Future<void>.delayed(Duration(seconds: secs ?? 2));
  return 'Waited ${secs ?? 2}s';
}
