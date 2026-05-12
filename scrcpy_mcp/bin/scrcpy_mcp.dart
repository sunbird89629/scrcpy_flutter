#!/usr/bin/env dart

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

void main(List<String> args) async {
  initLogging();
  final adbPath = args.isNotEmpty ? args[0] : 'adb';
  final adb = AdbClient(adbPath: adbPath);
  final scrcpyAdb = ScrcpyMcpAdb(adb);

  final session = await ScrcpySessionImpl.create(adb: scrcpyAdb);
  final server = ScrcpyMcpServer(
    session: session,
    adb: scrcpyAdb,
    recordingAdb: scrcpyAdb,
  );

  final transport = StdioServerTransport();
  await server.mcpServer.connect(transport);
}
