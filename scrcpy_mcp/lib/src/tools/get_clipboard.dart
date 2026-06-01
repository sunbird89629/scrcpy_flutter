import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

/// Reads the current text content of the device clipboard.
///
/// Sends a GetClipboard request to the device via scrcpy and waits up to
/// 5 seconds for the device to respond with clipboard contents.
class GetClipboardTool extends McpTool {
  GetClipboardTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'get_clipboard';

  @override
  String get description =>
      'Read the current text content of the device clipboard.';

  @override
  ToolInputSchema get inputSchema => JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    try {
      final text = await _session.getClipboard();
      logger.fine('get_clipboard: "${McpTool.truncate(text, 100)}"');
      return CallToolResult.fromContent([TextContent(text: text)]);
    } on TimeoutException {
      return CallToolResult(
        content: [TextContent(text: 'Timed out waiting for clipboard response.')],
        isError: true,
      );
    }
  }
}
