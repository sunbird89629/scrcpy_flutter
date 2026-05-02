import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// MCP server exposing scrcpy operations via the Model Context Protocol.
class ScrcpyMcpServer {
  /// Creates a scrcpy MCP server.
  ///
  /// [viewController] is shared with the UI so both the widget and the MCP
  /// server operate on the same mirroring session.
  /// [adb] provides device enumeration and screenshot capture.
  ScrcpyMcpServer({
    required ScrcpyViewController viewController,
    required ScrcpyAdb adb,
  })  : _viewController = viewController,
        _adb = adb {
    _mcpServer = McpServer(
      const Implementation(name: 'scrcpy-mcp', version: '0.2.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
          resources: ServerCapabilitiesResources(),
          prompts: ServerCapabilitiesPrompts(),
        ),
      ),
    );
    _registerAll();
  }

  final ScrcpyViewController _viewController;
  final ScrcpyAdb _adb;
  late final McpServer _mcpServer;
  String? _connectedDeviceId;

  /// The underlying [McpServer] used to connect to a transport.
  McpServer get mcpServer => _mcpServer;

  void _registerAll() {
    _registerTools();
    _registerResources();
    _registerPrompts();
  }

  void _registerTools() {
    _mcpServer
      ..registerTool(
        'list_devices',
        description: 'List connected Android devices.',
        inputSchema: JsonSchema.object(properties: {}),
        callback: _listDevices,
      )
      ..registerTool(
        'start_mirroring',
        description: 'Start screen mirroring for a device.',
        inputSchema: JsonSchema.object(
          properties: {
            'device_id': JsonSchema.string(
              description: 'The Android device serial',
            ),
          },
          required: ['device_id'],
        ),
        callback: _startMirroring,
      )
      ..registerTool(
        'stop_mirroring',
        description: 'Stop the active mirroring session.',
        inputSchema: JsonSchema.object(properties: {}),
        callback: _stopMirroring,
      )
      ..registerTool(
        'inject_key',
        description: 'Send a key event to the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'keycode': JsonSchema.integer(
              description: 'Android KeyEvent keycode',
            ),
            'action': JsonSchema.integer(
              description: 'Key action: 0=down, 1=up (default: 0)',
            ),
          },
          required: ['keycode'],
        ),
        callback: _injectKey,
      )
      ..registerTool(
        'inject_touch',
        description: 'Send a touch event to the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'x': JsonSchema.integer(description: 'X coordinate'),
            'y': JsonSchema.integer(description: 'Y coordinate'),
            'width': JsonSchema.integer(description: 'Screen width'),
            'height': JsonSchema.integer(description: 'Screen height'),
            'action': JsonSchema.integer(
              description: 'Touch action: 0=down, 1=up, 2=move (default: 0)',
            ),
          },
          required: ['x', 'y', 'width', 'height'],
        ),
        callback: _injectTouch,
      )
      ..registerTool(
        'inject_text',
        description: 'Input text on the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'text': JsonSchema.string(description: 'Text to input'),
          },
          required: ['text'],
        ),
        callback: _injectText,
      )
      ..registerTool(
        'inject_scroll',
        description: 'Send a scroll event to the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'x': JsonSchema.integer(description: 'X coordinate'),
            'y': JsonSchema.integer(description: 'Y coordinate'),
            'width': JsonSchema.integer(description: 'Screen width'),
            'height': JsonSchema.integer(description: 'Screen height'),
            'hScroll': JsonSchema.integer(
              description: 'Horizontal scroll amount',
            ),
            'vScroll': JsonSchema.integer(
              description: 'Vertical scroll amount',
            ),
          },
          required: ['x', 'y', 'width', 'height', 'hScroll', 'vScroll'],
        ),
        callback: _injectScroll,
      )
      ..registerTool(
        'take_screenshot',
        description: 'Capture the current screen of the device as a PNG image.',
        inputSchema: JsonSchema.object(
          properties: {
            'device_id': JsonSchema.string(
              description:
                  'Device serial (optional, uses connected device if omitted)',
            ),
          },
        ),
        callback: _takeScreenshot,
      );
  }

  void _registerResources() {
    _mcpServer
      ..registerResource(
        'Connected Devices',
        'device://list',
        (
          description: 'List of currently connected Android devices.',
          mimeType: 'application/json',
        ),
        _readDeviceList,
      )
      ..registerResource(
        'Mirroring Status',
        'mirroring://status',
        (
          description: 'Current mirroring session status.',
          mimeType: 'application/json',
        ),
        _readMirroringStatus,
      );
  }

  void _registerPrompts() {
    _mcpServer
      ..registerPrompt(
        'control_device',
        description: 'Assist with Android device control via scrcpy.',
        argsSchema: {
          'device_id': const PromptArgumentDefinition(
            description: 'The device to control (optional if only one device)',
          ),
        },
        callback: _getControlDevicePrompt,
      )
      ..registerPrompt(
        'troubleshoot',
        description: 'Help diagnose and fix device connection issues.',
        argsSchema: {
          'issue': const PromptArgumentDefinition(
            description: 'Description of the issue encountered',
          ),
        },
        callback: _getTroubleshootPrompt,
      );
  }

  // ── Tool implementations ──────────────────────────────────────────────────

  Future<CallToolResult> _listDevices(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final devices = await _adb.getDevices();
    return CallToolResult.fromContent(
      [TextContent(text: jsonEncode(devices))],
    );
  }

  Future<CallToolResult> _startMirroring(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceId = args['device_id'] as String;
    try {
      await _viewController.start(deviceId);
      _connectedDeviceId = deviceId;
      return CallToolResult.fromContent([
        TextContent(
          text: jsonEncode({
            'status': 'mirroring',
            'device_id': deviceId,
            'proxy_url': _viewController.server?.proxyUrl,
            'player_url': _viewController.server?.playerUrl,
          }),
        ),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed to start mirroring: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _stopMirroring(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_viewController.isConnected) {
      return CallToolResult.fromContent(
        [const TextContent(text: 'No active mirroring session.')],
      );
    }
    await _viewController.stop();
    _connectedDeviceId = null;
    return CallToolResult.fromContent(
      [const TextContent(text: 'Mirroring stopped.')],
    );
  }

  Future<CallToolResult> _injectKey(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_viewController.isConnected) {
      return const CallToolResult(
        content: [TextContent(text: 'No active mirroring session.')],
        isError: true,
      );
    }
    final keycode = args['keycode'] as int;
    final action = args['action'] as int? ?? ScrcpyAction.down;
    _viewController.sendControlMessage(
      ScrcpyInjectKeyMessage(action: action, keycode: keycode),
    );
    return CallToolResult.fromContent([
      TextContent(
        text: 'Key event sent: keycode=$keycode, action=$action',
      ),
    ]);
  }

  Future<CallToolResult> _injectTouch(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_viewController.isConnected) {
      return const CallToolResult(
        content: [TextContent(text: 'No active mirroring session.')],
        isError: true,
      );
    }
    final x = args['x'] as int;
    final y = args['y'] as int;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final action = args['action'] as int? ?? ScrcpyAction.down;
    _viewController.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: action,
        pointerId: 0,
        x: x,
        y: y,
        width: width,
        height: height,
      ),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Touch event sent: ($x, $y) action=$action'),
    ]);
  }

  Future<CallToolResult> _injectText(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_viewController.isConnected) {
      return const CallToolResult(
        content: [TextContent(text: 'No active mirroring session.')],
        isError: true,
      );
    }
    final text = args['text'] as String;
    _viewController.injectText(text);
    return CallToolResult.fromContent(
      [TextContent(text: 'Text sent: "$text"')],
    );
  }

  Future<CallToolResult> _injectScroll(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_viewController.isConnected) {
      return const CallToolResult(
        content: [TextContent(text: 'No active mirroring session.')],
        isError: true,
      );
    }
    final x = args['x'] as int;
    final y = args['y'] as int;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final hScroll = args['hScroll'] as int;
    final vScroll = args['vScroll'] as int;
    _viewController.sendControlMessage(
      ScrcpyInjectScrollMessage(
        x: x,
        y: y,
        width: width,
        height: height,
        hScroll: hScroll,
        vScroll: vScroll,
      ),
    );
    return CallToolResult.fromContent([
      TextContent(
        text: 'Scroll event sent: ($x, $y) h=$hScroll v=$vScroll',
      ),
    ]);
  }

  Future<CallToolResult> _takeScreenshot(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceIdArg = args['device_id'] as String?;
    final deviceId = deviceIdArg ?? _connectedDeviceId;
    if (deviceId != null) {
      return _doScreenshot(deviceId);
    }
    final devices = await _adb.getDevices();
    if (devices.isEmpty) {
      return const CallToolResult(
        content: [TextContent(text: 'No devices connected.')],
        isError: true,
      );
    }
    return _doScreenshot(devices.first);
  }

  Future<CallToolResult> _doScreenshot(String deviceId) async {
    try {
      final pngBytes = await _adb.takeScreenshot(deviceId);
      return CallToolResult.fromContent([
        ImageContent(
          data: base64Encode(pngBytes),
          mimeType: 'image/png',
        ),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Screenshot failed: $e')],
        isError: true,
      );
    }
  }

  // ── Resource implementations ──────────────────────────────────────────────

  Future<ReadResourceResult> _readDeviceList(
    Uri uri,
    RequestHandlerExtra extra,
  ) async {
    final devices = await _adb.getDevices();
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: jsonEncode(devices),
        ),
      ],
    );
  }

  Future<ReadResourceResult> _readMirroringStatus(
    Uri uri,
    RequestHandlerExtra extra,
  ) async {
    final status = <String, dynamic>{
      'active': _viewController.isConnected,
      if (_connectedDeviceId != null) 'device_id': _connectedDeviceId,
    };
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: jsonEncode(status),
        ),
      ],
    );
  }

  // ── Prompt implementations ────────────────────────────────────────────────

  Future<GetPromptResult> _getControlDevicePrompt(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    final deviceId = args?['device_id'] as String?;
    final devices = await _adb.getDevices();
    final deviceInfo = deviceId != null
        ? 'Target device: $deviceId'
        : 'Available devices: ${devices.join(", ")}';

    return GetPromptResult(
      description: 'Device control assistant',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'You are an Android device control assistant.\n\n'
                '$deviceInfo\n\n'
                'Available tools:\n'
                '- list_devices, start_mirroring, stop_mirroring\n'
                '- inject_key (Home=3, Back=4, AppSwitch=187)\n'
                '- inject_touch, inject_text, inject_scroll\n'
                '- take_screenshot\n\n'
                'Help the user control their Android device.',
          ),
        ),
      ],
    );
  }

  Future<GetPromptResult> _getTroubleshootPrompt(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    final issue = args?['issue'] as String?;
    final devices = await _adb.getDevices();

    return GetPromptResult(
      description: 'Device troubleshooting assistant',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text: 'You are an Android device troubleshooting assistant.\n\n'
                'Connected devices: '
                '${devices.isEmpty ? "none" : devices.join(", ")}\n'
                '${issue != null ? "Reported issue: $issue\n" : ""}\n'
                'Common issues:\n'
                '1. No devices: Check USB connection, enable USB debugging\n'
                '2. Connection refused: Run adb kill-server\n'
                '3. Mirroring fails: Check scrcpy server version\n'
                '4. Black screen: Device may be locked\n\n'
                'Help the user diagnose and resolve their issue.',
          ),
        ),
      ],
    );
  }
}
