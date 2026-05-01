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
  }

  Future<CallToolResult> _listDevices(CallToolRequest request) async {
    final devices = await _adb.getDevices();
    return CallToolResult(
      content: [Content.text(text: jsonEncode(devices))],
    );
  }
}
