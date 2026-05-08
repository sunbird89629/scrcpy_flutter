import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

List<McpTool> inputTools(ScrcpySession session) => [
      McpTool(
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
            TextContent(
                text: 'Key event sent: keycode=$keycode, action=$action'),
          ]);
        },
      ),
      McpTool(
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
      ),
      McpTool(
        name: 'inject_text',
        description: 'Input text on the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'text': JsonSchema.string(description: 'Text to input'),
          },
          required: ['text'],
        ),
        callback: (args, extra) async {
          if (!session.isConnected) {
            return const CallToolResult(
              content: [TextContent(text: 'No active mirroring session.')],
              isError: true,
            );
          }
          final text = args['text'] as String;
          session.injectText(text);
          return CallToolResult.fromContent(
            [TextContent(text: 'Text sent: "$text"')],
          );
        },
      ),
      McpTool(
        name: 'inject_scroll',
        description: 'Send a scroll event to the device.',
        inputSchema: JsonSchema.object(
          properties: {
            'x': JsonSchema.integer(description: 'X coordinate'),
            'y': JsonSchema.integer(description: 'Y coordinate'),
            'width': JsonSchema.integer(description: 'Screen width'),
            'height': JsonSchema.integer(description: 'Screen height'),
            'hScroll': JsonSchema.integer(
              description: 'Horizontal scroll amount',
            ),
            'vScroll': JsonSchema.integer(
              description: 'Vertical scroll amount',
            ),
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
      ),
    ];
