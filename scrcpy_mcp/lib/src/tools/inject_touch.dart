import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

/// Sends a touch event at the given screen coordinates via the scrcpy
/// control socket.
///
/// Coordinates are in device pixels; pass the actual screen resolution as
/// `width`/`height` so scrcpy can scale correctly. Requires an active
/// mirroring session.
class InjectTouchTool extends McpTool {
  InjectTouchTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'inject_touch';

  @override
  String get description => 'Send a touch event to the device.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'x': JsonSchema.integer(description: 'X coordinate'),
      'y': JsonSchema.integer(description: 'Y coordinate'),
      'width': JsonSchema.integer(description: 'Screen width'),
      'height': JsonSchema.integer(description: 'Screen height'),
      'action': JsonSchema.integer(
        description: 'Touch action: 0=down, 1=up, 2=move (default: 0)',
      ),
    },
    required: ['x', 'y', 'width', 'height'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final x = args['x'] as int;
    final y = args['y'] as int;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final action = args['action'] as int? ?? ScrcpyAction.down;
    final (vw, vh) = _session.videoSize(width, height);
    final (rx, ry) = _session.rescale(x, y, width, height);
    logger.fine('inject_touch: ($x,$y) → rescaled ($rx,$ry), video=${vw}x$vh, action=$action');
    _session.sendControlMessage(
      ScrcpyInjectTouchMessage(
        action: action,
        pointerId: 0,
        x: rx,
        y: ry,
        width: vw,
        height: vh,
      ),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Touch event sent: ($x, $y) action=$action'),
    ]);
  }
}
