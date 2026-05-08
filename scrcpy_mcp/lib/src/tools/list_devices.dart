import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

/// Lists all Android devices currently visible to ADB.
///
/// Returns a JSON-encoded array of device serial strings, e.g.
/// `["emulator-5554", "192.168.1.5:5555"]`.
class ListDevicesTool implements McpTool {
  ListDevicesTool(this._adb);
  final ScrcpyAdb _adb;

  @override
  String get name => 'list_devices';

  @override
  String get description => 'List connected Android devices.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> call(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final devices = await _adb.getDevices();
    return CallToolResult.fromContent(
      [TextContent(text: jsonEncode(devices))],
    );
  }
}
