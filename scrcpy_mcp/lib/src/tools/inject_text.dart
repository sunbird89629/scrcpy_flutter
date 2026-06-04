import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

/// Types text on the device using scrcpy's text-injection API.
///
/// Supports Unicode; the text is sent as-is without simulating individual
/// key events. Requires an active mirroring session.
class InjectTextTool extends McpTool {
  InjectTextTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'inject_text';

  @override
  String get description => 'Input text on the device.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {'text': JsonSchema.string(description: 'Text to input')},
    required: ['text'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final text = args['text'] as String;
    logger.fine(
      'inject_text: len=${text.length}, text="${McpTool.truncate(text, 60)}"',
    );
    _session.injectText(text);
    return CallToolResult.fromContent([
      TextContent(text: 'Text sent: "$text"'),
    ]);
  }
}
