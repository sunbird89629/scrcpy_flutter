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
}
