import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../agent/action_parser.dart';
import '../agent/agent_config.dart';
import '../agent/llm_client.dart';
import '../agent/phone_agent.dart';
import '../mcp_tool.dart';
import '../session_context.dart';

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

    // The model reasons on the ADB screencap, whose resolution is the device's
    // native resolution — NOT the (maxSize-scaled) scrcpy video resolution.
    // Capture each screenshot's real dimensions and feed them to touch
    // injection so coordinates map back to the exact space the model saw.
    // Using video dimensions here scales every tap wrong and misses targets.
    (int, int)? lastShotSize;

    final agent = PhoneAgent(
      config: _config,
      llmClient: _llmClient,
      takeScreenshot: () async {
        final bytes = await _adb.takeScreenshot(deviceId);
        lastShotSize = _pngSize(bytes) ?? lastShotSize;
        return (base64: base64Encode(bytes), mimeType: 'image/png');
      },
      actionRunner: (action) => _executeAction(action, deviceId, lastShotSize),
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

  Future<String> _executeAction(
    PhoneAction action,
    String deviceId,
    (int, int)? screenSize,
  ) {
    switch (action) {
      case final DoAction doAction:
        return _runDoAction(doAction, deviceId, screenSize);
      case final FinishAction finishAction:
        return Future.value(finishAction.message);
    }
  }

  Future<String> _runDoAction(
    DoAction action,
    String deviceId,
    (int, int)? screenSize,
  ) async {
    switch (action.action) {
      case 'Tap':
        return _tap(action, deviceId, screenSize);
      case 'Swipe':
        return _swipe(action, deviceId, screenSize);
      case 'Type':
        return _typeText(action, deviceId);
      case 'Launch':
        return _launch(action, deviceId);
      case 'Back':
        return _back(deviceId);
      case 'Home':
        return _home(deviceId);
      case 'Long Press':
        return _longPress(action, deviceId, screenSize);
      case 'Double Tap':
        return _doubleTap(action, deviceId, screenSize);
      case 'Wait':
        return _wait(action);
      case 'Take_over':
        return _takeOver(action);
      default:
        return Future.value('Unknown action: ${action.action}');
    }
  }

  // ── Action implementations ─────────────────────────────────────────────────

  Future<String> _tap(
    DoAction action,
    String deviceId,
    (int, int)? screenSize,
  ) async {
    if (action.element == null || action.element!.length < 2) {
      return 'Error: Tap missing element coordinates';
    }
    final size = await _resolveSize(deviceId, screenSize);
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: 0, // down
        pointerId: 0,
        x: action.element![0],
        y: action.element![1],
        width: size.$1,
        height: size.$2,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: 1, // up
        pointerId: 0,
        x: action.element![0],
        y: action.element![1],
        width: size.$1,
        height: size.$2,
      ),
    );
    return 'Tapped at (${action.element![0]}, ${action.element![1]})';
  }

  Future<String> _swipe(
    DoAction action,
    String deviceId,
    (int, int)? screenSize,
  ) async {
    if (action.start == null ||
        action.end == null ||
        action.start!.length < 2 ||
        action.end!.length < 2) {
      return 'Error: Swipe missing start/end coordinates';
    }
    final size = await _resolveSize(deviceId, screenSize);
    _session.sendControlMessage(
      ScrcpyInjectScrollMessage(
        x: action.start![0],
        y: action.start![1],
        width: size.$1,
        height: size.$2,
        hScroll: action.end![0] - action.start![0],
        vScroll: action.end![1] - action.start![1],
      ),
    );
    return 'Swiped from (${action.start![0]}, ${action.start![1]}) '
        'to (${action.end![0]}, ${action.end![1]})';
  }

  Future<String> _typeText(DoAction action, String deviceId) async {
    if (action.text == null) return 'Error: Type missing text';
    _session.injectText(action.text!);
    return 'Typed: ${action.text}';
  }

  Future<String> _launch(DoAction action, String deviceId) async {
    if (action.app == null) return 'Error: Launch missing app name';
    final pkg = _appNameToPackage[action.app] ?? action.app!;
    final result = await _adb.shell(
      ['monkey', '-p', pkg, '-c', 'android.intent.category.LAUNCHER', '1'],
      deviceId: deviceId,
    );
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

  Future<String> _longPress(
    DoAction action,
    String deviceId,
    (int, int)? screenSize,
  ) async {
    if (action.element == null || action.element!.length < 2) {
      return 'Error: Long Press missing coordinates';
    }
    final size = await _resolveSize(deviceId, screenSize);
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: 0, // down
        pointerId: 0,
        x: action.element![0],
        y: action.element![1],
        width: size.$1,
        height: size.$2,
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: 1, // up
        pointerId: 0,
        x: action.element![0],
        y: action.element![1],
        width: size.$1,
        height: size.$2,
      ),
    );
    return 'Long pressed at (${action.element![0]}, ${action.element![1]})';
  }

  Future<String> _doubleTap(
    DoAction action,
    String deviceId,
    (int, int)? screenSize,
  ) async {
    if (action.element == null || action.element!.length < 2) {
      return 'Error: Double Tap missing coordinates';
    }
    await _tap(action, deviceId, screenSize);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _tap(action, deviceId, screenSize);
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Resolution that touch coordinates are expressed in. Prefer the actual
  /// screenshot dimensions ([screenSize], read from the PNG the model saw);
  /// fall back to the device's native resolution via `wm size`. Never the
  /// scrcpy video resolution — that is maxSize-scaled and does not match the
  /// screencap coordinate space the model reasons in.
  Future<(int, int)> _resolveSize(
    String deviceId,
    (int, int)? screenSize,
  ) async => screenSize ?? await _screenSize(deviceId);

  Future<(int, int)> _screenSize(String deviceId) async {
    final result = await _adb.shell(['wm', 'size'], deviceId: deviceId);
    final m = RegExp(r'(\d+)x(\d+)').firstMatch(result.stdout as String);
    if (m != null) {
      return (int.parse(m.group(1)!), int.parse(m.group(2)!));
    }
    return (1080, 1920);
  }

  /// Reads `(width, height)` from a PNG's IHDR chunk, or null if [bytes] is not
  /// a PNG. The dimensions are big-endian uint32s at byte offsets 16 and 20,
  /// right after the 8-byte signature, the 4-byte IHDR length, and the "IHDR"
  /// tag.
  static (int, int)? _pngSize(Uint8List bytes) {
    if (bytes.length < 24) return null;
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return null;
    }
    final bd = ByteData.sublistView(bytes);
    return (bd.getUint32(16), bd.getUint32(20));
  }
}
