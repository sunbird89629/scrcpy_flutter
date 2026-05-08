import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

import '../mcp_tool.dart';
import '../recording_controller.dart';

McpTool stopRecordingTool(RecordingController controller) => McpTool(
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
    );
