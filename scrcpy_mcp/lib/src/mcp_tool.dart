import 'package:logger_utils/logger_utils.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:scrcpy_client/scrcpy_client.dart';

final _logger = Logger('scrcpy.mcp');

/// Base contract for all MCP tool implementations.
///
/// Each tool exposes a [name], a human-readable [description], an [inputSchema]
/// describing accepted arguments, and an [execute] handler that implements the
/// tool logic. [call] is the concrete entry point — it wraps [execute] with
/// timing and structured logging so subclasses never need to repeat that
/// boilerplate.
///
/// [notConnectedResult] is a shared constant for tools that require an active
/// mirroring session — avoids duplicating the same error object across tools.
abstract class McpTool {
  String get name;
  String get description;
  ToolInputSchema get inputSchema;

  Future<CallToolResult> call(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    _logger.info('$name ← $args');
    final sw = Stopwatch()..start();
    final result = await execute(args, extra);
    final ms = sw.elapsedMilliseconds;
    if (result.isError == true) {
      _logger.warning('$name → ${ms}ms ERROR');
    } else {
      _logger.info('$name → ${ms}ms');
    }
    return result;
  }

  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  );

  static const notConnectedResult = CallToolResult(
    content: [TextContent(text: 'No active mirroring session.')],
    isError: true,
  );
}

/// Coordinate rescaling for scrcpy control messages.
///
/// scrcpy silently drops touch/scroll events whose reported (width, height)
/// does not equal the encoded video size. This extension resolves the video
/// dimensions and rescales device-resolution coordinates into video space.
extension ScrcpyCoordRescale on ScrcpySession {
  (int vw, int vh) videoSize(int width, int height) =>
      (videoWidth ?? width, videoHeight ?? height);

  (int x, int y) rescale(int x, int y, int width, int height) {
    final (vw, vh) = videoSize(width, height);
    return (x * vw ~/ width, y * vh ~/ height);
  }
}
