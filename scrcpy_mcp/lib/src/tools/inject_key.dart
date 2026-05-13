import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

/// Sends an Android key event via the scrcpy control socket.
///
/// Common keycodes: Home = 3, Back = 4, AppSwitch = 187, Power = 26.
/// Requires an active mirroring session.
class InjectKeyTool extends McpTool {
  InjectKeyTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'inject_key';

  @override
  String get description => 'Send a key event to the device.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'keycode': JsonSchema.integer(
        description: 'Android KeyEvent keycode',
      ),
      'action': JsonSchema.integer(
        description: 'Key action: 0=down, 1=up (default: 0)',
      ),
    },
    required: ['keycode'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final keycode = args['keycode'] as int;
    final action = args['action'] as int? ?? ScrcpyAction.down;
    _session.sendControlMessage(
      ScrcpyInjectKeyMessage(action: action, keycode: keycode),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Key event sent: keycode=$keycode, action=$action'),
    ]);
  }
}
