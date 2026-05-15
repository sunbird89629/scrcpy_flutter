import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class RotateDeviceTool extends McpTool {
  RotateDeviceTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'rotate_device';

  @override
  String get description => 'Rotate the device display 90 degrees.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(const ScrcpyRotateDeviceMessage());
    return CallToolResult.fromContent([TextContent(text: 'Rotate sent.')]);
  }
}
