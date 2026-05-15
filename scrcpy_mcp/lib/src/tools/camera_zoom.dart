import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class CameraZoomTool extends McpTool {
  CameraZoomTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'camera_zoom';

  @override
  String get description => 'Zoom the device camera in or out by one step.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'direction': JsonSchema.string(
        description: 'Zoom direction: "in" or "out"',
      ),
    },
    required: ['direction'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final direction = args['direction'] as String;
    if (direction == 'in') {
      _session.sendControlMessage(const ScrcpyCameraZoomInMessage());
      return CallToolResult.fromContent([TextContent(text: 'Camera zoomed in.')]);
    } else if (direction == 'out') {
      _session.sendControlMessage(const ScrcpyCameraZoomOutMessage());
      return CallToolResult.fromContent([TextContent(text: 'Camera zoomed out.')]);
    }
    return CallToolResult(
      content: [TextContent(text: 'Invalid direction: "$direction". Use "in" or "out".')],
      isError: true,
    );
  }
}
