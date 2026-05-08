import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';
import '../session_context.dart';

/// Stops the active scrcpy mirroring session and clears the connected device.
///
/// Returns immediately without error when no session is active.
class StopMirroringTool implements McpTool {
  StopMirroringTool(this._session, this._ctx);
  final ScrcpySession _session;
  final SessionContext _ctx;

  @override
  String get name => 'stop_mirroring';

  @override
  String get description => 'Stop the active mirroring session.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> call(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) {
      return CallToolResult.fromContent(
        [const TextContent(text: 'No active mirroring session.')],
      );
    }
    await _session.stop();
    _ctx.connectedDeviceId = null;
    return CallToolResult.fromContent(
      [const TextContent(text: 'Mirroring stopped.')],
    );
  }
}
