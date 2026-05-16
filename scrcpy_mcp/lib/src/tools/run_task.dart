import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../agent/agent_config.dart';
import '../agent/llm_client.dart';
import '../agent/phone_agent.dart';
import '../mcp_tool.dart';
import '../session_context.dart';

class RunTaskTool extends McpTool {
  RunTaskTool({
    required AgentConfig config,
    required LlmClient llmClient,
    required List<McpTool> tools,
    required ScrcpySession session,
    required SessionContext ctx,
  })  : _config = config,
        _llmClient = llmClient,
        _tools = tools,
        _session = session,
        _ctx = ctx;

  final AgentConfig _config;
  final LlmClient _llmClient;
  final List<McpTool> _tools;
  final ScrcpySession _session;
  final SessionContext _ctx;

  @override
  String get name => 'run_task';

  @override
  String get description =>
      'Run a natural language task on an Android device using an AI agent. '
      'The agent autonomously takes screenshots, taps, and types to complete '
      'the task, then returns a plain-text result.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'device_id': JsonSchema.string(
        description: 'Device serial to operate on (from list_devices)',
      ),
      'message': JsonSchema.string(
        description: 'Natural language task, e.g. "打开微信" or "查询违章信息"',
      ),
    },
    required: ['device_id', 'message'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceId = args['device_id'] as String;
    final message = args['message'] as String;

    if (!_session.isConnected) {
      await _session.start(deviceId);
      _ctx.connectedDeviceId = deviceId;
    }

    final toolMap = {for (final t in _tools) t.name: t};
    final toolSchemas = _tools
        .map((t) => ToolSchema(
              name: t.name,
              description: t.description,
              parameters: t.inputSchema.toJson(),
            ))
        .toList();

    Future<({String text, String? imageBase64, String? imageMimeType})>
        execTool(String toolName, Map<String, dynamic> toolArgs) async {
      final tool = toolMap[toolName];
      if (tool == null) {
        return (
          text: 'Error: unknown tool "$toolName"',
          imageBase64: null,
          imageMimeType: null,
        );
      }
      final result = await tool.execute(toolArgs, extra);
      if (result.isError == true) {
        final errText = result.content
            .whereType<TextContent>()
            .map((c) => c.text)
            .join('\n');
        return (
          text: 'Error: $errText',
          imageBase64: null,
          imageMimeType: null
        );
      }
      String? imgBase64;
      String? imgMime;
      final textParts = <String>[];
      for (final content in result.content) {
        if (content is TextContent) textParts.add(content.text);
        if (content is ImageContent) {
          imgBase64 = content.data;
          imgMime = content.mimeType;
        }
      }
      return (
        text: textParts.join('\n'),
        imageBase64: imgBase64,
        imageMimeType: imgMime,
      );
    }

    final agent = PhoneAgent(
      config: _config,
      llmClient: _llmClient,
      tools: toolSchemas,
      executeToolCall: execTool,
    );

    try {
      final result = await agent.run(message);
      return CallToolResult.fromStructuredContent({
        'result': result.result,
        'steps': result.steps,
        'success': result.success,
      });
    } catch (e) {
      return CallToolResult.fromStructuredContent({
        'result': e.toString(),
        'steps': 0,
        'success': false,
      });
    }
  }
}
