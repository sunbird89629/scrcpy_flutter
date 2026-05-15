import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class CollapsePanelsTool extends McpTool {
  CollapsePanelsTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'collapse_panels';

  @override
  String get description => 'Collapse any open notification or settings panel.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(const ScrcpyCollapsePanelsMessage());
    return CallToolResult.fromContent([TextContent(text: 'Panels collapsed.')]);
  }
}
