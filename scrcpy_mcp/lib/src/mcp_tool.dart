import 'package:mcp_dart/mcp_dart.dart';

/// Base contract for all MCP tool implementations.
///
/// Each tool exposes a [name], a human-readable [description], an [inputSchema]
/// describing accepted arguments, and a [call] handler that executes the tool
/// logic and returns a [CallToolResult].
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
  );

  static const notConnectedResult = CallToolResult(
    content: [TextContent(text: 'No active mirroring session.')],
    isError: true,
  );
}
