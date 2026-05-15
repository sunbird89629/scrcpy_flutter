import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class PressBackTool extends McpTool {
  PressBackTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'press_back';

  @override
  String get description =>
      'Send a Back button press to the device (down then up). '
      'Also wakes the screen if it is off.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(
      const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down),
    );
    _session.sendControlMessage(
      const ScrcpyBackOrScreenOnMessage(ScrcpyAction.up),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Back button pressed.'),
    ]);
  }
}
