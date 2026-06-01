import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class SetScreenPowerTool extends McpTool {
  SetScreenPowerTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'set_screen_power';

  @override
  String get description => 'Turn the device screen on or off.';

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
    _session.sendControlMessage(ScrcpySetDisplayPowerMessage(on: on));
    return CallToolResult.fromContent([
      TextContent(text: on ? 'Screen turned on.' : 'Screen turned off.'),
    ]);
  }
}
