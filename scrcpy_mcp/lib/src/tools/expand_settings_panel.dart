import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class ExpandSettingsPanelTool extends McpTool {
  ExpandSettingsPanelTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'expand_settings_panel';

  @override
  String get description =>
      'Expand the quick-settings panel (equivalent to a two-finger swipe down).';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(const ScrcpyExpandSettingsPanelMessage());
    return CallToolResult.fromContent([
      TextContent(text: 'Settings panel expanded.'),
    ]);
  }
}
