import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

McpTool injectScrollTool(ScrcpySession session) => McpTool(
      name: 'inject_scroll',
      description: 'Send a scroll event to the device.',
      inputSchema: JsonSchema.object(
        properties: {
          'x': JsonSchema.integer(description: 'X coordinate'),
          'y': JsonSchema.integer(description: 'Y coordinate'),
          'width': JsonSchema.integer(description: 'Screen width'),
          'height': JsonSchema.integer(description: 'Screen height'),
          'hScroll': JsonSchema.integer(description: 'Horizontal scroll amount'),
          'vScroll': JsonSchema.integer(description: 'Vertical scroll amount'),
        },
        required: ['x', 'y', 'width', 'height', 'hScroll', 'vScroll'],
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
        final hScroll = args['hScroll'] as int;
        final vScroll = args['vScroll'] as int;
        session.sendControlMessage(
          ScrcpyInjectScrollMessage(
            x: x,
            y: y,
            width: width,
            height: height,
            hScroll: hScroll,
            vScroll: vScroll,
          ),
        );
        return CallToolResult.fromContent([
          TextContent(
              text: 'Scroll event sent: ($x, $y) h=$hScroll v=$vScroll'),
        ]);
      },
    );
