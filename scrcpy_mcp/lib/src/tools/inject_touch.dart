import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

McpTool injectTouchTool(ScrcpySession session) => McpTool(
      name: 'inject_touch',
      description: 'Send a touch event to the device.',
      inputSchema: JsonSchema.object(
        properties: {
          'x': JsonSchema.integer(description: 'X coordinate'),
          'y': JsonSchema.integer(description: 'Y coordinate'),
          'width': JsonSchema.integer(description: 'Screen width'),
          'height': JsonSchema.integer(description: 'Screen height'),
          'action': JsonSchema.integer(
            description: 'Touch action: 0=down, 1=up, 2=move (default: 0)',
          ),
        },
        required: ['x', 'y', 'width', 'height'],
      ),
      callback: (args, extra) async {
        if (!session.isConnected) {
          return const CallToolResult(
            content: [TextContent(text: 'No active mirroring session.')],
            isError: true,
          );
        }
        final x = args['x'] as int;
        final y = args['y'] as int;
        final width = args['width'] as int;
        final height = args['height'] as int;
        final action = args['action'] as int? ?? ScrcpyAction.down;
        session.sendControlMessage(
          ScrcpyInjectTouchMessage(
            action: action,
            pointerId: 0,
            x: x,
            y: y,
            width: width,
            height: height,
          ),
        );
        return CallToolResult.fromContent([
          TextContent(text: 'Touch event sent: ($x, $y) action=$action'),
        ]);
      },
    );
