import 'package:mcp_dart/mcp_dart.dart';

typedef ToolCallback = Future<CallToolResult> Function(
  Map<String, dynamic> args,
  RequestHandlerExtra extra,
);

class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.callback,
  });

  final String name;
  final String description;
  final ToolInputSchema inputSchema;
  final ToolCallback callback;
}
