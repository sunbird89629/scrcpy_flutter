#!/usr/bin/env dart
// Copyright (c) 2024, the Dart project authors.
// Please see the AUTHORS file or the project root for details.

import 'dart:io';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

/// MCP server for scrcpy — Android screen mirroring via MCP protocol.
///
/// Usage: dart run scrcpy_mcp
///
/// Communicates via stdin/stdout using the MCP protocol.
/// Configure your MCP client to launch this command.
void main(List<String> args) async {
  final adbPath = args.isNotEmpty ? args[0] : 'adb';
  final adb = AdbClient(adbPath: adbPath);

  final server = ScrcpyMcpServer(
    stdioChannel(input: stdin, output: stdout),
    adb: ScrcpyMcpAdb(adb),
  );

  await server.done;
  exit(0);
}
