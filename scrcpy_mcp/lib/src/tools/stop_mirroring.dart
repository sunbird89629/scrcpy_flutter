import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';
import '../session_context.dart';

McpTool stopMirroringTool(ScrcpySession session, SessionContext ctx) => McpTool(
      name: 'stop_mirroring',
      description: 'Stop the active mirroring session.',
      inputSchema: JsonSchema.object(properties: {}),
      callback: (args, extra) async {
        if (!session.isConnected) {
          return CallToolResult.fromContent(
            [const TextContent(text: 'No active mirroring session.')],
          );
        }
        await session.stop();
        ctx.connectedDeviceId = null;
        return CallToolResult.fromContent(
          [const TextContent(text: 'Mirroring stopped.')],
        );
      },
    );
