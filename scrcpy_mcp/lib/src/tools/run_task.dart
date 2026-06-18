import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../agent/agent_config.dart';
import '../agent/agent_model_client.dart';
import '../agent/phone_agent.dart';
import '../agent/scrcpy_action_runner.dart';
import '../agent/screenshot_util.dart';
import '../mcp_tool.dart';
import '../session_context.dart';

class RunTaskTool extends McpTool {
  RunTaskTool({
    required AgentConfig config,
    required AgentModelClient client,
    required ScrcpyAdb adb,
    required ScrcpySession session,
    required SessionContext ctx,
  }) : _config = config,
       _client = client,
       _adb = adb,
       _session = session,
       _ctx = ctx;

  final AgentConfig _config;
  final AgentModelClient _client;
  final ScrcpyAdb _adb;
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
      logger.fine('run_task: auto-connecting device=$deviceId');
      await _session.start(deviceId);
      _ctx.connectedDeviceId = deviceId;
    }
    logger.fine('run_task: message="$message"');

    final runner = ScrcpyActionRunner(
      session: _session,
      adb: _adb,
      deviceId: deviceId,
    );
    final agent = PhoneAgent(
      config: _config,
      client: _client,
      takeScreenshot: blankRetryingScreenshot(
        () => _adb.takeScreenshot(deviceId),
      ),
      actionRunner: runner.run,
    );

    try {
      final result = await agent.run(message);
      logger.fine(
        'run_task: completed, steps=${result.steps}, success=${result.success}',
      );
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
