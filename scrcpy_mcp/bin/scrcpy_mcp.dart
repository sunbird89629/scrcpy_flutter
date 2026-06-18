#!/usr/bin/env dart

import 'dart:io';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:mcp_dart/mcp_dart.dart' hide Logger;
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

void main(List<String> args) async {
  initLogging();
  final adbPath = args.isNotEmpty ? args[0] : 'adb';
  final adb = AdbClient(adbPath: adbPath);
  final scrcpyAdb = ScrcpyMcpAdb(adb);

  final session = await ScrcpySessionImpl.create(adb: scrcpyAdb);

  final client = AutoGLMOfficialClient.fromTest();
  final sopEnv = Platform.environment['SCRCPY_MCP_SOP_DIR'];
  final sopDir = (sopEnv != null && sopEnv.isNotEmpty) ? sopEnv : null;

  final server = ScrcpyMcpServer(
    session: session,
    adb: scrcpyAdb,
    recordingAdb: scrcpyAdb,
    agentConfig: AgentConfig(sopDir: sopDir),
    client: client,
  );

  final transport = StdioServerTransport();
  await server.mcpServer.connect(transport);
}
