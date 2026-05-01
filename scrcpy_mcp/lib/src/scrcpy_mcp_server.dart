import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// MCP server exposing scrcpy operations.
final class ScrcpyMcpServer extends MCPServer with ToolsSupport {
  /// Creates a scrcpy MCP server.
  ScrcpyMcpServer(
    super.channel, {
    required ScrcpyAdb adb,
    super.protocolLogSink,
  })  : _adb = adb,
        super.fromStreamChannel(
          implementation: Implementation(
            name: 'scrcpy-mcp',
            version: '0.2.0',
          ),
          instructions:
              'Use this server to control Android devices via scrcpy. '
              'List devices, start/stop screen mirroring, and inject input events.',
        );

  final ScrcpyAdb _adb;
  ScrcpyServer? _activeServer;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    _registerTools();
    return super.initialize(request);
  }

  void _registerTools() {
    registerTool(
      Tool(
        name: 'list_devices',
        description: 'List connected Android devices.',
        inputSchema: ObjectSchema(),
      ),
      _listDevices,
    );

    registerTool(
      Tool(
        name: 'start_mirroring',
        description: 'Start screen mirroring for a device.',
        inputSchema: ObjectSchema(
          properties: {
            'device_id': Schema.string(
              description: 'The Android device serial',
            ),
          },
          required: ['device_id'],
        ),
      ),
      _startMirroring,
    );

    registerTool(
      Tool(
        name: 'stop_mirroring',
        description: 'Stop the active mirroring session.',
        inputSchema: ObjectSchema(),
      ),
      _stopMirroring,
    );

    registerTool(
      Tool(
        name: 'inject_key',
        description: 'Send a key event to the device.',
        inputSchema: ObjectSchema(
          properties: {
            'keycode': Schema.int(
              description: 'Android KeyEvent keycode',
            ),
            'action': Schema.int(
              description: 'Key action: 0=down, 1=up (default: 0)',
            ),
          },
          required: ['keycode'],
        ),
      ),
      _injectKey,
    );

    registerTool(
      Tool(
        name: 'inject_touch',
        description: 'Send a touch event to the device.',
        inputSchema: ObjectSchema(
          properties: {
            'x': Schema.int(description: 'X coordinate'),
            'y': Schema.int(description: 'Y coordinate'),
            'width': Schema.int(description: 'Screen width'),
            'height': Schema.int(description: 'Screen height'),
            'action': Schema.int(
              description:
                  'Touch action: 0=down, 1=up, 2=move (default: 0)',
            ),
          },
          required: ['x', 'y', 'width', 'height'],
        ),
      ),
      _injectTouch,
    );

    registerTool(
      Tool(
        name: 'inject_text',
        description: 'Input text on the device.',
        inputSchema: ObjectSchema(
          properties: {
            'text': Schema.string(description: 'Text to input'),
          },
          required: ['text'],
        ),
      ),
      _injectText,
    );

    registerTool(
      Tool(
        name: 'inject_scroll',
        description: 'Send a scroll event to the device.',
        inputSchema: ObjectSchema(
          properties: {
            'x': Schema.int(description: 'X coordinate'),
            'y': Schema.int(description: 'Y coordinate'),
            'width': Schema.int(description: 'Screen width'),
            'height': Schema.int(description: 'Screen height'),
            'hScroll': Schema.int(
              description: 'Horizontal scroll amount',
            ),
            'vScroll': Schema.int(
              description: 'Vertical scroll amount',
            ),
          },
          required: ['x', 'y', 'width', 'height', 'hScroll', 'vScroll'],
        ),
      ),
      _injectScroll,
    );
  }

  Future<CallToolResult> _listDevices(CallToolRequest request) async {
    final devices = await _adb.getDevices();
    return CallToolResult(
      content: [Content.text(text: jsonEncode(devices))],
    );
  }

  Future<CallToolResult> _startMirroring(CallToolRequest request) async {
    final deviceId = request.arguments!['device_id'] as String;

    // Stop existing session if any
    await _activeServer?.stop();

    _activeServer = ScrcpyServer(
      adb: _adb,
      deviceId: deviceId,
      logger: const NoOpScrcpyLogger(),
    );

    try {
      await _activeServer!.start();
      final status = {
        'status': 'mirroring',
        'device_id': deviceId,
        'proxy_url': _activeServer!.proxyUrl,
        'player_url': _activeServer!.playerUrl,
      };
      return CallToolResult(
        content: [Content.text(text: jsonEncode(status))],
      );
    } catch (e) {
      return CallToolResult(
        isError: true,
        content: [Content.text(text: 'Failed to start mirroring: $e')],
      );
    }
  }

  Future<CallToolResult> _stopMirroring(CallToolRequest request) async {
    if (_activeServer == null) {
      return CallToolResult(
        content: [Content.text(text: 'No active mirroring session.')],
      );
    }

    await _activeServer!.stop();
    _activeServer = null;

    return CallToolResult(
      content: [Content.text(text: 'Mirroring stopped.')],
    );
  }

  Future<CallToolResult> _injectKey(CallToolRequest request) async {
    if (_activeServer == null) {
      return CallToolResult(
        isError: true,
        content: [Content.text(text: 'No active mirroring session.')],
      );
    }

    final keycode = request.arguments!['keycode'] as int;
    final action =
        request.arguments!['action'] as int? ?? ScrcpyAction.down;

    _activeServer!.sendControlMessage(
      ScrcpyInjectKeyMessage(action: action, keycode: keycode),
    );

    return CallToolResult(
      content: [
        Content.text(
          text: 'Key event sent: keycode=$keycode, action=$action',
        ),
      ],
    );
  }

  Future<CallToolResult> _injectTouch(CallToolRequest request) async {
    if (_activeServer == null) {
      return CallToolResult(
        isError: true,
        content: [Content.text(text: 'No active mirroring session.')],
      );
    }

    final x = request.arguments!['x'] as int;
    final y = request.arguments!['y'] as int;
    final width = request.arguments!['width'] as int;
    final height = request.arguments!['height'] as int;
    final action =
        request.arguments!['action'] as int? ?? ScrcpyAction.down;

    _activeServer!.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: action,
        pointerId: 0,
        x: x,
        y: y,
        width: width,
        height: height,
      ),
    );

    return CallToolResult(
      content: [
        Content.text(
          text: 'Touch event sent: ($x, $y) action=$action',
        ),
      ],
    );
  }

  Future<CallToolResult> _injectText(CallToolRequest request) async {
    if (_activeServer == null) {
      return CallToolResult(
        isError: true,
        content: [Content.text(text: 'No active mirroring session.')],
      );
    }

    final text = request.arguments!['text'] as String;

    _activeServer!.sendControlMessage(ScrcpyInjectTextMessage(text));

    return CallToolResult(
      content: [Content.text(text: 'Text sent: "$text"')],
    );
  }

  Future<CallToolResult> _injectScroll(CallToolRequest request) async {
    if (_activeServer == null) {
      return CallToolResult(
        isError: true,
        content: [Content.text(text: 'No active mirroring session.')],
      );
    }

    final x = request.arguments!['x'] as int;
    final y = request.arguments!['y'] as int;
    final width = request.arguments!['width'] as int;
    final height = request.arguments!['height'] as int;
    final hScroll = request.arguments!['hScroll'] as int;
    final vScroll = request.arguments!['vScroll'] as int;

    _activeServer!.sendControlMessage(
      ScrcpyInjectScrollMessage(
        x: x,
        y: y,
        width: width,
        height: height,
        hScroll: hScroll,
        vScroll: vScroll,
      ),
    );

    return CallToolResult(
      content: [
        Content.text(
          text: 'Scroll event sent: ($x, $y) h=$hScroll v=$vScroll',
        ),
      ],
    );
  }
}
