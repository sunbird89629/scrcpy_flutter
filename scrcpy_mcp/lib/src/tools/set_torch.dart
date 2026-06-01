import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class SetTorchTool extends McpTool {
  SetTorchTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'set_torch';

  @override
  String get description => 'Turn the device flashlight/torch on or off.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'on': JsonSchema.boolean(
        description: 'true to turn on, false to turn off',
      ),
    },
    required: ['on'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final on = args['on'] as bool;
    _session.sendControlMessage(ScrcpyCameraSetTorchMessage(on: on));
    return CallToolResult.fromContent([
      TextContent(text: on ? 'Torch turned on.' : 'Torch turned off.'),
    ]);
  }
}
