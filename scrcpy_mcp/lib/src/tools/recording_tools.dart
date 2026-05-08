import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';
import '../recording_controller.dart';
import '../session_context.dart';

List<McpTool> recordingTools(
  RecordingController controller,
  SessionContext ctx,
  ScrcpySession session,
) =>
    [
      McpTool(
        name: 'start_recording',
        description: 'Start screen recording on the active mirroring device '
            '(max 180 s, Android limit). '
            'Protected content may record as black.',
        inputSchema: JsonSchema.object(
          properties: {
            'bitrate': JsonSchema.integer(
              description: 'Video bitrate in bps (default: 4000000)',
            ),
            'max_time': JsonSchema.integer(
              description: 'Max duration in seconds, Android limit is 180 '
                  '(default: 180)',
            ),
          },
        ),
        callback: (args, extra) async {
          if (!session.isConnected) {
            return const CallToolResult(
              content: [
                TextContent(
                  text:
                      'No active mirroring session. Call start_mirroring first.',
                ),
              ],
              isError: true,
            );
          }
          if (controller.isRecording) {
            final s = controller.status;
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
          final deviceId = ctx.connectedDeviceId;
          if (deviceId == null) {
            return const CallToolResult(
              content: [
                TextContent(
                  text:
                      'No active mirroring session. Call start_mirroring first.',
                ),
              ],
              isError: true,
            );
          }
          final bitrate = args['bitrate'] as int? ?? 4000000;
          final maxTime = args['max_time'] as int? ?? 180;
          try {
            final remotePath = await controller.start(
              deviceId,
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
        },
      ),
      McpTool(
        name: 'stop_recording',
        description:
            'Stop the active screen recording and save to local disk.',
        inputSchema: JsonSchema.object(
          properties: {
            'save_path': JsonSchema.string(
              description: 'Local file path '
                  '(default: ~/Downloads/scrcpy_records/rec_<timestamp>.mp4)',
            ),
          },
        ),
        callback: (args, extra) async {
          if (!controller.isRecording) {
            return CallToolResult.fromContent(
              [const TextContent(text: 'No active recording.')],
            );
          }
          final savePath = args['save_path'] as String?;
          try {
            final localPath = await controller.stop(savePath: savePath);
            final sizeBytes = await File(localPath).length();
            return CallToolResult.fromContent([
              TextContent(
                text: jsonEncode({
                  'status': 'finished',
                  'local_path': localPath,
                  'size_bytes': sizeBytes,
                }),
              ),
            ]);
          } on Exception catch (e) {
            return CallToolResult(
              content: [TextContent(text: 'Failed to stop recording: $e')],
              isError: true,
            );
          }
        },
      ),
    ];
