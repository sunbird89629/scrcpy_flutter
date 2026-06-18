import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../agent/agent_config.dart';
import '../agent/agent_model_client.dart';
import '../agent/phone_agent.dart';
import '../agent/scrcpy_action_runner.dart';
import '../agent/screenshot_util.dart';
import '../agent/sop/foreground_package.dart';
import '../agent/sop/sop_record.dart';
import '../agent/sop/sop_retriever.dart';
import '../agent/sop/sop_store.dart';
import '../agent/sop/sop_writer.dart';
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

    final sopDir = _config.sopDir;
    SopStore? store;
    String? package;
    String? guidance;
    if (sopDir != null) {
      try {
        store = SopStore(sopDir);
        package = await foregroundPackage(_adb, deviceId);
        if (package != null) {
          final picked = await SopRetriever(_client).select(
            taskText: message,
            candidates: await store.load(package),
          );
          if (picked.isNotEmpty) guidance = _formatGuidance(picked);
        }
      } catch (e) {
        logger.warning('sop retrieve failed: $e');
      }
    }

    try {
      final result = await agent.run(message, guidance: guidance);
      logger.fine(
        'run_task: completed, steps=${result.steps}, success=${result.success}',
      );

      if (store != null && package != null) {
        try {
          await SopWriter(_client, store).write(
            package: package,
            taskText: message,
            success: result.success,
            trajectory: result.trajectory,
          );
        } catch (e) {
          logger.warning('sop writeback failed: $e');
        }
      }

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

String _formatGuidance(List<SopRecord> sops) {
  final pos = sops.where((s) => s.polarity == SopPolarity.positive);
  final neg = sops.where((s) => s.polarity == SopPolarity.negative);
  final b = StringBuffer();
  if (pos.isNotEmpty) {
    b.writeln('可参考以下成功流程：');
    for (final s in pos) b.writeln('- ${s.intent}：${s.steps.join(' → ')}');
  }
  if (neg.isNotEmpty) {
    b.writeln('注意避免以下坑：');
    for (final s in neg) {
      b.writeln('- ${s.intent}：${s.pitfall ?? s.steps.join(' → ')}');
    }
  }
  return b.toString().trim();
}
