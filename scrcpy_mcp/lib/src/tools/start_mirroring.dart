import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';
import '../session_context.dart';

/// Starts a scrcpy mirroring session for the specified device.
///
/// On success, sets `SessionContext.connectedDeviceId` and returns the
/// `proxy_url` (MPEG-TS stream) and `player_url` (web player) for the
/// active session.
class StartMirroringTool extends McpTool {
  StartMirroringTool(this._session, this._ctx);
  final ScrcpySession _session;
  final SessionContext _ctx;

  @override
  String get name => 'start_mirroring';

  @override
  String get description => 'Start screen mirroring for a device.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'device_id': JsonSchema.string(
        description: 'The Android device serial',
      ),
    },
    required: ['device_id'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceId = args['device_id'] as String;
    try {
      await _session.start(deviceId);
      _ctx.connectedDeviceId = deviceId;
      return CallToolResult.fromContent([
        TextContent(
          text: jsonEncode({
            'status': 'mirroring',
            'device_id': deviceId,
            'video_width': _session.videoWidth,
            'video_height': _session.videoHeight,
          }),
        ),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed to start mirroring: $e')],
        isError: true,
      );
    }
  }
}
