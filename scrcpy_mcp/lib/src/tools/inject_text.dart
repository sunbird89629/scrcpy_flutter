import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

McpTool injectTextTool(ScrcpySession session) => McpTool(
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
    );
