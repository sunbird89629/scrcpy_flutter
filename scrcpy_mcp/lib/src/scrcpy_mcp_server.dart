import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// MCP server exposing scrcpy operations.
final class ScrcpyMcpServer extends MCPServer
    with ToolsSupport, ResourcesSupport, PromptsSupport {
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
    _registerResources();
    _registerPrompts();
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

  void _registerPrompts() {
    addPrompt(
      Prompt(
        name: 'control_device',
        description:
            'Assist with Android device control via scrcpy. '
            'Helps with navigation, input, and screen mirroring.',
        arguments: [
          PromptArgument(
            name: 'device_id',
            description: 'The device to control (optional if only one device)',
          ),
        ],
      ),
      _getControlDevicePrompt,
    );

    addPrompt(
      Prompt(
        name: 'troubleshoot',
        description: 'Help diagnose and fix device connection issues.',
        arguments: [
          PromptArgument(
            name: 'issue',
            description: 'Description of the issue encountered',
          ),
        ],
      ),
      _getTroubleshootPrompt,
    );
  }

  void _registerResources() {
    addResource(
      Resource(
        uri: 'device://list',
        name: 'Connected Devices',
        description: 'List of currently connected Android devices.',
        mimeType: 'application/json',
      ),
      _readDeviceList,
    );

    addResource(
      Resource(
        uri: 'mirroring://status',
        name: 'Mirroring Status',
        description: 'Current mirroring session status.',
        mimeType: 'application/json',
      ),
      _readMirroringStatus,
    );
  }

  Future<GetPromptResult> _getControlDevicePrompt(
    GetPromptRequest request,
  ) async {
    final deviceId = request.arguments?['device_id'] as String?;

    final devices = await _adb.getDevices();
    final deviceInfo = deviceId != null
        ? 'Target device: $deviceId'
        : 'Available devices: ${devices.join(", ")}';

    return GetPromptResult(
      description: 'Device control assistant',
      messages: [
        PromptMessage(
          role: Role.user,
          content: Content.text(
            text: 'You are an Android device control assistant.\n\n'
                '$deviceInfo\n\n'
                'You can use the following tools:\n'
                '- list_devices: See connected devices\n'
                '- start_mirroring: Start screen mirroring\n'
                '- stop_mirroring: Stop mirroring\n'
                '- inject_key: Send key events '
                    '(Home=3, Back=4, AppSwitch=187)\n'
                '- inject_touch: Send touch events\n'
                '- inject_text: Type text\n'
                '- inject_scroll: Scroll the screen\n\n'
                'Help the user control their Android device.',
          ),
        ),
      ],
    );
  }

  Future<GetPromptResult> _getTroubleshootPrompt(
    GetPromptRequest request,
  ) async {
    final issue = request.arguments?['issue'] as String?;

    final devices = await _adb.getDevices();

    return GetPromptResult(
      description: 'Device troubleshooting assistant',
      messages: [
        PromptMessage(
          role: Role.user,
          content: Content.text(
            text: 'You are an Android device '
                'troubleshooting assistant.\n\n'
                'Connected devices: '
                '${devices.isEmpty ? "none" : devices.join(", ")}\n'
                '${issue != null ? "Reported issue: $issue\n" : ""}\n'
                'Common issues and solutions:\n'
                '1. No devices found: Check USB connection, '
                'enable USB debugging\n'
                '2. Connection refused: Restart adb server '
                '(adb kill-server)\n'
                '3. Mirroring fails: Check scrcpy server '
                'version compatibility\n'
                '4. Black screen: Device may be locked, '
                'try pressing power key\n\n'
                'Help the user diagnose and resolve their device issue.',
          ),
        ),
      ],
    );
  }

  Future<CallToolResult> _listDevices(CallToolRequest request) async {
    final devices = await _adb.getDevices();
    return CallToolResult(
      content: [Content.text(text: jsonEncode(devices))],
    );
  }

  Future<CallToolResult> _startMirroring(CallToolRequest request) async {
    final deviceId =
        (request.arguments!['device_id'] as String?)!;

    // Stop existing session if any
    await _activeServer?.stop();

    _activeServer = ScrcpyServer(
      adb: _adb,
      deviceId: deviceId,
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
    } on Exception catch (e) {
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

    final keycode =
        (request.arguments!['keycode'] as int?)!;
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

    final x = (request.arguments!['x'] as int?)!;
    final y = (request.arguments!['y'] as int?)!;
    final width = (request.arguments!['width'] as int?)!;
    final height = (request.arguments!['height'] as int?)!;
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

    final text = (request.arguments!['text'] as String?)!;

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

    final x = (request.arguments!['x'] as int?)!;
    final y = (request.arguments!['y'] as int?)!;
    final width = (request.arguments!['width'] as int?)!;
    final height = (request.arguments!['height'] as int?)!;
    final hScroll = (request.arguments!['hScroll'] as int?)!;
    final vScroll = (request.arguments!['vScroll'] as int?)!;

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

  Future<ReadResourceResult> _readDeviceList(
    ReadResourceRequest request,
  ) async {
    final devices = await _adb.getDevices();
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: 'device://list',
          text: jsonEncode(devices),
          mimeType: 'application/json',
        ),
      ],
    );
  }

  Future<ReadResourceResult> _readMirroringStatus(
    ReadResourceRequest request,
  ) async {
    final status = <String, dynamic>{
      'active': _activeServer != null,
      if (_activeServer != null) ...{
        'device_id': _activeServer!.deviceId,
        'proxy_url': _activeServer!.proxyUrl,
        'player_url': _activeServer!.playerUrl,
      },
    };
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: 'mirroring://status',
          text: jsonEncode(status),
          mimeType: 'application/json',
        ),
      ],
    );
  }

  @override
  Future<void> shutdown() async {
    await _activeServer?.stop();
    _activeServer = null;
    await super.shutdown();
  }
}
