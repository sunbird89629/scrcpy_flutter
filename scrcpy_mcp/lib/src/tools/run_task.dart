import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../agent/action_parser.dart';
import '../agent/agent_config.dart';
import '../agent/llm_client.dart';
import '../agent/phone_agent.dart';
import '../mcp_tool.dart';
import '../session_context.dart';

/// autoglm-phone emits coordinates normalized to a 1000×1000 grid (see the
/// official handler: `x = element[0] / 1000 * screen_width`). scrcpy's touch
/// protocol scales `x / frameWidth * deviceWidth`, so passing the raw model
/// coordinate with a 1000×1000 frame lands at the correct device pixel,
/// independent of the actual device resolution.
const _kCoordSpace = 1000;

// Android KeyEvent constants for clearing a text field before typing.
const _keycodeA = 29; // KEYCODE_A
const _keycodeDel = 67; // KEYCODE_DEL (backspace) — deletes the selection
const _keycodeCtrlLeft = 113; // KEYCODE_CTRL_LEFT
const _metaCtrlOn = 0x1000; // META_CTRL_ON

/// Common app name → package name mappings for autoglm-phone's Launch action.
const _appNameToPackage = {
  'Chrome': 'com.android.chrome',
  'chrome': 'com.android.chrome',
  '微信': 'com.tencent.mm',
  'WeChat': 'com.tencent.mm',
  '支付宝': 'com.eg.android.AlipayGphone',
  '美团': 'com.sankuai.meituan',
  '大众点评': 'com.dianping.v1',
  '抖音': 'com.ss.android.ugc.aweme',
  '小红书': 'com.xingin.xhs',
  '百度': 'com.baidu.searchbox',
  '高德地图': 'com.autonavi.minimap',
  '淘宝': 'com.taobao.taobao',
  '京东': 'com.jingdong.app.mall',
  '拼多多': 'com.xunmeng.pinduoduo',
};

class RunTaskTool extends McpTool {
  RunTaskTool({
    required AgentConfig config,
    required LlmClient llmClient,
    required ScrcpyAdb adb,
    required ScrcpySession session,
    required SessionContext ctx,
  }) : _config = config,
       _llmClient = llmClient,
       _adb = adb,
       _session = session,
       _ctx = ctx;

  final AgentConfig _config;
  final LlmClient _llmClient;
  final ScrcpyAdb _adb;
  final ScrcpySession _session;
  final SessionContext _ctx;

  @override
  String get name => 'run_task';

  @override
  String get description =>
      'Run a natural language task on an Android device using an AI agent. '
      'The agent autonomously takes screenshots, taps, and types to complete '
      'the task, then returns a plain-text result.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'device_id': JsonSchema.string(
        description: 'Device serial to operate on (from list_devices)',
      ),
      'message': JsonSchema.string(
        description: 'Natural language task, e.g. "打开微信" or "查询违章信息"',
      ),
    },
    required: ['device_id', 'message'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceId = args['device_id'] as String;
    final message = args['message'] as String;

    if (!_session.isConnected) {
      logger.fine('run_task: auto-connecting device=$deviceId');
      await _session.start(deviceId);
      _ctx.connectedDeviceId = deviceId;
    }
    logger.fine('run_task: message="$message"');

    final agent = PhoneAgent(
      config: _config,
      llmClient: _llmClient,
      takeScreenshot: () async {
        final bytes = await _adb.takeScreenshot(deviceId);
        return (base64: base64Encode(bytes), mimeType: 'image/png');
      },
      actionRunner: (action) => _executeAction(action, deviceId),
    );

    try {
      final result = await agent.run(message);
      logger.fine(
        'run_task: completed, steps=${result.steps}, success=${result.success}',
      );
      return CallToolResult.fromStructuredContent({
        'result': result.result,
        'steps': result.steps,
        'success': result.success,
      });
    } catch (e) {
      return CallToolResult.fromStructuredContent({
        'result': e.toString(),
        'steps': 0,
        'success': false,
      });
    }
  }

  Future<String> _executeAction(PhoneAction action, String deviceId) {
    switch (action) {
      case final DoAction doAction:
        return _runDoAction(doAction, deviceId);
      case final FinishAction finishAction:
        return Future.value(finishAction.message);
    }
  }

  Future<String> _runDoAction(DoAction action, String deviceId) async {
    switch (action.action) {
      case 'Tap':
        return _tap(action, deviceId);
      case 'Swipe':
        return _swipe(action, deviceId);
      case 'Type':
      case 'Type_Name':
        return _typeText(action, deviceId);
      case 'Launch':
        return _launch(action, deviceId);
      case 'Note':
        // Recording-only action: nothing to do on-device, just acknowledge so
        // the agent loop continues.
        return Future.value('Noted');
      case 'Call_API':
        // Summarize/comment action with no on-device effect in this headless
        // flow; acknowledge with the model's instruction so the loop continues.
        return Future.value('Acknowledged: ${action.message ?? 'summary'}');
      case 'Back':
        return _back(deviceId);
      case 'Home':
        return _home(deviceId);
      case 'Long Press':
        return _longPress(action, deviceId);
      case 'Double Tap':
        return _doubleTap(action, deviceId);
      case 'Wait':
        return _wait(action);
      case 'Take_over':
        return _takeOver(action);
      default:
        return Future.value('Unknown action: ${action.action}');
    }
  }

  // ── Action implementations ─────────────────────────────────────────────────

  Future<String> _tap(DoAction action, String deviceId) async {
    if (action.element == null || action.element!.length < 2) {
      return 'Error: Tap missing element coordinates';
    }
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: 0, // down
        pointerId: 0,
        x: action.element![0],
        y: action.element![1],
        width: _kCoordSpace,
        height: _kCoordSpace,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: 1, // up
        pointerId: 0,
        x: action.element![0],
        y: action.element![1],
        width: _kCoordSpace,
        height: _kCoordSpace,
      ),
    );
    return 'Tapped at (${action.element![0]}, ${action.element![1]})';
  }

  Future<String> _swipe(DoAction action, String deviceId) async {
    if (action.start == null ||
        action.end == null ||
        action.start!.length < 2 ||
        action.end!.length < 2) {
      return 'Error: Swipe missing start/end coordinates';
    }
    _session.sendControlMessage(
      ScrcpyInjectScrollMessage(
        x: action.start![0],
        y: action.start![1],
        width: _kCoordSpace,
        height: _kCoordSpace,
        hScroll: action.end![0] - action.start![0],
        vScroll: action.end![1] - action.start![1],
      ),
    );
    return 'Swiped from (${action.start![0]}, ${action.start![1]}) '
        'to (${action.end![0]}, ${action.end![1]})';
  }

  Future<String> _typeText(DoAction action, String deviceId) async {
    if (action.text == null) return 'Error: Type missing text';
    // autoglm-phone's Type *replaces* a field's content, so clear it first
    // (select-all, then Del) — otherwise text is appended onto whatever is
    // already there. Mirrors the official handler's clear_text-before-type.
    _selectAll();
    _sendKey(_keycodeDel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _session.injectText(action.text!);
    return 'Typed: ${action.text}';
  }

  /// Selects all text in the focused field via a Ctrl+A chord: Ctrl down,
  /// A down/up (with Ctrl in the metastate), Ctrl up — the way scrcpy injects
  /// modifier combinations.
  void _selectAll() {
    _session.sendControlMessage(
      const ScrcpyInjectKeyMessage(action: 0, keycode: _keycodeCtrlLeft),
    );
    _sendKey(_keycodeA, metastate: _metaCtrlOn);
    _session.sendControlMessage(
      const ScrcpyInjectKeyMessage(action: 1, keycode: _keycodeCtrlLeft),
    );
  }

  /// Sends a key down+up pair (optionally with modifier [metastate]).
  void _sendKey(int keycode, {int metastate = 0}) {
    _session.sendControlMessage(
      ScrcpyInjectKeyMessage(action: 0, keycode: keycode, metastate: metastate),
    );
    _session.sendControlMessage(
      ScrcpyInjectKeyMessage(action: 1, keycode: keycode, metastate: metastate),
    );
  }

  Future<String> _launch(DoAction action, String deviceId) async {
    if (action.app == null) return 'Error: Launch missing app name';
    final pkg = _appNameToPackage[action.app] ?? action.app!;
    final result = await _adb.shell([
      'monkey',
      '-p',
      pkg,
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ], deviceId: deviceId);
    final ok =
        result.exitCode == 0 && !(result.stdout as String).contains('Error');
    return ok ? 'Launched ${action.app} ($pkg)' : 'Failed to launch $pkg';
  }

  Future<String> _back(String deviceId) async {
    _session.sendControlMessage(const ScrcpyBackOrScreenOnMessage(4)); // back
    return 'Pressed Back';
  }

  Future<String> _home(String deviceId) async {
    _session.sendControlMessage(
      const ScrcpyInjectKeyMessage(action: 0, keycode: 3), // down, home
    );
    return 'Pressed Home';
  }

  Future<String> _longPress(DoAction action, String deviceId) async {
    if (action.element == null || action.element!.length < 2) {
      return 'Error: Long Press missing coordinates';
    }
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: 0, // down
        pointerId: 0,
        x: action.element![0],
        y: action.element![1],
        width: _kCoordSpace,
        height: _kCoordSpace,
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: 1, // up
        pointerId: 0,
        x: action.element![0],
        y: action.element![1],
        width: _kCoordSpace,
        height: _kCoordSpace,
      ),
    );
    return 'Long pressed at (${action.element![0]}, ${action.element![1]})';
  }

  Future<String> _doubleTap(DoAction action, String deviceId) async {
    if (action.element == null || action.element!.length < 2) {
      return 'Error: Double Tap missing coordinates';
    }
    await _tap(action, deviceId);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _tap(action, deviceId);
    return 'Double tapped at (${action.element![0]}, ${action.element![1]})';
  }

  Future<String> _wait(DoAction action) async {
    final secs = int.tryParse(
      (action.duration ?? '2s').replaceAll(RegExp('[^0-9]'), ''),
    );
    await Future<void>.delayed(Duration(seconds: secs ?? 2));
    return 'Waited ${secs ?? 2}s';
  }

  String _takeOver(DoAction action) =>
      'Manual intervention requested: ${action.message ?? 'no details'}';
}
