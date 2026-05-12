import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

/// Sends a swipe gesture as a sequence of touch events: DOWN at the start,
/// `steps` interpolated MOVE events spread over `durationMs`, then UP at the
/// end.
///
/// Unlike `inject_scroll` (which sends a mouse-wheel `ACTION_SCROLL` event),
/// `inject_swipe` simulates a finger gesture and is reliably handled by
/// virtually every scrollable Android view. Requires an active mirroring
/// session.
class InjectSwipeTool extends McpTool {
  InjectSwipeTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'inject_swipe';

  @override
  String get description =>
      'Send a swipe gesture (DOWN → MOVE × N → UP) to the device.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'x1': JsonSchema.integer(description: 'Start X coordinate'),
      'y1': JsonSchema.integer(description: 'Start Y coordinate'),
      'x2': JsonSchema.integer(description: 'End X coordinate'),
      'y2': JsonSchema.integer(description: 'End Y coordinate'),
      'width': JsonSchema.integer(description: 'Screen width'),
      'height': JsonSchema.integer(description: 'Screen height'),
      'durationMs': JsonSchema.integer(
        description: 'Total swipe duration in ms (default 300). '
            'Shorter = fling, longer = slow drag.',
      ),
      'steps': JsonSchema.integer(
        description: 'Number of intermediate MOVE events (default 16, min 1)',
      ),
    },
    required: ['x1', 'y1', 'x2', 'y2', 'width', 'height'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final x1 = args['x1'] as int;
    final y1 = args['y1'] as int;
    final x2 = args['x2'] as int;
    final y2 = args['y2'] as int;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final durationMs = args['durationMs'] as int? ?? 300;
    final steps = args['steps'] as int? ?? 16;

    if (steps < 1) {
      return const CallToolResult(
        content: [TextContent(text: 'steps must be >= 1')],
        isError: true,
      );
    }

    final (vw, vh) = _session.videoSize(width, height);
    final stepDelay = Duration(microseconds: durationMs * 1000 ~/ steps);

    void sendTouch(int action, int x, int y) {
      final (rx, ry) = _session.rescale(x, y, width, height);
      _session.sendControlMessage(ScrcpyInjectTouchMessage(
        action: action,
        pointerId: 0,
        x: rx,
        y: ry,
        width: vw,
        height: vh,
      ));
    }

    sendTouch(ScrcpyAction.down, x1, y1);
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(stepDelay);
      sendTouch(
        ScrcpyAction.move,
        x1 + ((x2 - x1) * i) ~/ steps,
        y1 + ((y2 - y1) * i) ~/ steps,
      );
    }
    sendTouch(ScrcpyAction.up, x2, y2);

    return CallToolResult.fromContent([
      TextContent(
        text: 'Swipe sent: ($x1, $y1) → ($x2, $y2) in ${durationMs}ms '
            '($steps steps)',
      ),
    ]);
  }
}
