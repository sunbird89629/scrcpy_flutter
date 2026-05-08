import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';
import '../session_context.dart';

List<McpTool> mirroringTools(ScrcpySession session, SessionContext ctx) => [
      McpTool(
        name: 'start_mirroring',
        description: 'Start screen mirroring for a device.',
        inputSchema: JsonSchema.object(
          properties: {
            'device_id': JsonSchema.string(
              description: 'The Android device serial',
            ),
          },
          required: ['device_id'],
        ),
        callback: (args, extra) async {
          final deviceId = args['device_id'] as String;
          try {
            await session.start(deviceId);
            ctx.connectedDeviceId = deviceId;
            return CallToolResult.fromContent([
              TextContent(
                text: jsonEncode({
                  'status': 'mirroring',
                  'device_id': deviceId,
                  'proxy_url': session.proxyUrl,
                  'player_url': session.playerUrl,
                }),
              ),
            ]);
          } on Exception catch (e) {
            return CallToolResult(
              content: [TextContent(text: 'Failed to start mirroring: $e')],
              isError: true,
            );
          }
        },
      ),
      McpTool(
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
      ),
    ];
