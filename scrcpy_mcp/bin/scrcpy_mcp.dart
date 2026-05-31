#!/usr/bin/env dart

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

final _log = Logger('scrcpy.mcp.bin');

void main(List<String> args) async {
  initLogging();
  final adbPath = args.isNotEmpty ? args[0] : 'adb';
  final adb = AdbClient(adbPath: adbPath);
  final scrcpyAdb = ScrcpyMcpAdb(adb);

  final session = await ScrcpySessionImpl.create(adb: scrcpyAdb);

  final agentConfig =
      OpenAiLlmClient.isConfigured ? AgentConfig.fromEnv() : null;
  final llmClient = OpenAiLlmClient.fromTest();
  // OpenAiLlmClient.isConfigured ? OpenAiLlmClient.fromEnv() : null;

  if (agentConfig != null) {
    _log.info('Agent enabled: model=${llmClient.model}, '
        'maxSteps=${agentConfig.maxSteps}');
  }

  final server = ScrcpyMcpServer(
    session: session,
    adb: scrcpyAdb,
    recordingAdb: scrcpyAdb,
    agentConfig: agentConfig,
    llmClient: llmClient,
  );

  final transport = StdioServerTransport();
  await server.mcpServer.connect(transport);
}
