import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class SetClipboardTool extends McpTool {
  SetClipboardTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'set_clipboard';

  @override
  String get description =>
      'Write text to the device clipboard. '
      'Pass paste=true to also paste immediately into the focused field.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'text': JsonSchema.string(description: 'Text to place on the clipboard'),
      'paste': JsonSchema.boolean(
        description: 'Whether to paste the text immediately (default: false)',
      ),
    },
    required: ['text'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final text = args['text'] as String;
    final paste = args['paste'] as bool? ?? false;
    _session.sendControlMessage(ScrcpySetClipboardMessage(text: text, paste: paste));
    return CallToolResult.fromContent([
      TextContent(text: paste ? 'Clipboard set and pasted.' : 'Clipboard set.'),
    ]);
  }
}
