import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

/// Sends a scroll event at the given screen coordinates via the scrcpy
/// control socket.
///
/// `hScroll`/`vScroll` are signed integers; positive values scroll
/// right/down, negative values scroll left/up. Requires an active
/// mirroring session.
class InjectScrollTool extends McpTool {
  InjectScrollTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'inject_scroll';

  @override
  String get description => 'Send a scroll event to the device.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'x': JsonSchema.integer(description: 'X coordinate'),
      'y': JsonSchema.integer(description: 'Y coordinate'),
      'width': JsonSchema.integer(description: 'Screen width'),
      'height': JsonSchema.integer(description: 'Screen height'),
      'hScroll': JsonSchema.integer(description: 'Horizontal scroll amount'),
      'vScroll': JsonSchema.integer(description: 'Vertical scroll amount'),
    },
    required: ['x', 'y', 'width', 'height', 'hScroll', 'vScroll'],
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
    final hScroll = args['hScroll'] as int;
    final vScroll = args['vScroll'] as int;
    _session.sendControlMessage(
      ScrcpyInjectScrollMessage(
        x: x,
        y: y,
        width: width,
        height: height,
        hScroll: hScroll,
        vScroll: vScroll,
      ),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Scroll event sent: ($x, $y) h=$hScroll v=$vScroll'),
    ]);
  }
}
