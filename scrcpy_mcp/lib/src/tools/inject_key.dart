import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

McpTool injectKeyTool(ScrcpySession session) => McpTool(
      name: 'inject_key',
      description: 'Send a key event to the device.',
      inputSchema: JsonSchema.object(
        properties: {
          'keycode': JsonSchema.integer(
            description: 'Android KeyEvent keycode',
          ),
          'action': JsonSchema.integer(
            description: 'Key action: 0=down, 1=up (default: 0)',
          ),
        },
        required: ['keycode'],
      ),
      callback: (args, extra) async {
        if (!session.isConnected) {
          return const CallToolResult(
            content: [TextContent(text: 'No active mirroring session.')],
            isError: true,
          );
        }
        final keycode = args['keycode'] as int;
        final action = args['action'] as int? ?? ScrcpyAction.down;
        session.sendControlMessage(
          ScrcpyInjectKeyMessage(action: action, keycode: keycode),
        );
        return CallToolResult.fromContent([
          TextContent(text: 'Key event sent: keycode=$keycode, action=$action'),
        ]);
      },
    );
