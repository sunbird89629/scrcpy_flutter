import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';
import '../recording_controller.dart';
import '../session_context.dart';

/// Starts an on-device screen recording via `adb shell screenrecord`.
///
/// The recording runs on the device and is saved to a temp path under
/// `/sdcard/`. Call `stop_recording` to stop and pull the file to the
/// local machine.
///
/// Android hard-limits recordings to 180 seconds. Protected content
/// (payment screens, DRM video) records as a black frame.
class StartRecordingTool implements McpTool {
  StartRecordingTool(this._controller, this._ctx, this._session);
  final RecordingController _controller;
  final SessionContext _ctx;
  final ScrcpySession _session;

  @override
  String get name => 'start_recording';

  @override
  String get description =>
      'Start screen recording on the active mirroring device '
      '(max 180 s, Android limit). '
      'Protected content may record as black.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'bitrate': JsonSchema.integer(
        description: 'Video bitrate in bps (default: 4000000)',
      ),
      'max_time': JsonSchema.integer(
        description:
            'Max duration in seconds, Android limit is 180 (default: 180)',
      ),
    },
  );

  @override
  Future<CallToolResult> call(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    if (_controller.isRecording) {
      final s = _controller.status;
      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'error': 'Already recording',
              'device_id': s.deviceId,
              'start_time': s.startTime?.toUtc().toIso8601String(),
            }),
          ),
        ],
        isError: true,
      );
    }
    final bitrate = args['bitrate'] as int? ?? 4000000;
    final maxTime = args['max_time'] as int? ?? 180;
    try {
      final remotePath = await _controller.start(
        _ctx.connectedDeviceId!,
        bitrate: bitrate,
        maxTime: maxTime,
      );
      return CallToolResult.fromContent([
        TextContent(
          text: jsonEncode({
            'status': 'recording',
            'path_on_device': remotePath,
          }),
        ),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed to start recording: $e')],
        isError: true,
      );
    }
  }
}
