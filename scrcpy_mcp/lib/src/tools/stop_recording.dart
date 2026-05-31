import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import '../mcp_tool.dart';
import '../recording_controller.dart';

/// Stops the active on-device screen recording and pulls the file to local disk.
///
/// The device-side recording process is killed via SIGINT so the MP4 container
/// is properly finalised before the file is pulled. The local save path
/// defaults to `~/Downloads/scrcpy_records/rec_<timestamp>.mp4`.
class StopRecordingTool extends McpTool {
  StopRecordingTool(this._controller);
  final RecordingController _controller;

  @override
  String get name => 'stop_recording';

  @override
  String get description =>
      'Stop the active screen recording and save to local disk.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'save_path': JsonSchema.string(
        description: 'Local file path '
            '(default: ~/Downloads/scrcpy_records/rec_<timestamp>.mp4)',
      ),
    },
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_controller.isRecording) {
      return CallToolResult.fromContent(
        [const TextContent(text: 'No active recording.')],
      );
    }
    final savePath = args['save_path'] as String?;
    logger.fine('stop_recording: savePath=${savePath ?? "(default)"}');
    try {
      final localPath = await _controller.stop(savePath: savePath);
      final sizeBytes = await File(localPath).length();
      logger.fine('stop_recording: saved to $localPath (${sizeBytes}B)');
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
  }
}
