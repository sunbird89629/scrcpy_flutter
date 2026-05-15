import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class ExpandNotificationPanelTool extends McpTool {
  ExpandNotificationPanelTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'expand_notification_panel';

  @override
  String get description =>
      'Expand the notification panel (equivalent to swiping down from the top).';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(const ScrcpyExpandNotificationPanelMessage());
    return CallToolResult.fromContent([
      TextContent(text: 'Notification panel expanded.'),
    ]);
  }
}
