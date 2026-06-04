#!/usr/bin/env dart
// Test client for scrcpy_mcp — exercises all MCP capabilities.

import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

Future<void> main(List<String> args) async {
  final adbArgs = <String>[];
  for (final arg in args) {
    if (!arg.startsWith('--')) adbArgs.add(arg);
  }

  stdout.writeln('=== scrcpy_mcp Test Client ===\n');

  // Workspace root = current working directory.
  final workspaceRoot = Directory.current.path;
  final serverPath = '$workspaceRoot/scrcpy_mcp/bin/scrcpy_mcp.dart';

  // The server depends on Flutter (dart:ui), so it needs `fvm dart run`
  // (Flutter SDK's dart) rather than plain `dart run`.
  final fvmExe = _findFvm();
  if (fvmExe == null) {
    stderr.writeln('Error: fvm not found. Install with: brew install fvm');
    exit(1);
  }

  stdout
    ..writeln('FVM: $fvmExe')
    ..writeln('Workspace: $workspaceRoot')
    ..writeln('Server: $serverPath\n');

  final client = McpClient(
    const Implementation(name: 'scrcpy-mcp-test', version: '0.1.0'),
  );

  // stderrMode defaults to inheritStdio, so server stderr flows to our stderr.
  final transport = StdioClientTransport(
    StdioServerParameters(
      command: fvmExe,
      args: ['dart', 'run', serverPath, ...adbArgs],
    ),
  );

  try {
    await client.connect(transport);

    // --- Tools ---
    await _listTools(client);
    await _callTool(client, 'list_devices');

    // Try mirroring if devices are available.
    final devicesResult = await client.callTool(
      const CallToolRequest(name: 'list_devices'),
    );
    final devicesText = _textOf(devicesResult) ?? '[]';
    if (devicesText != '[]') {
      final deviceList = jsonDecode(devicesText) as List;
      if (deviceList.isNotEmpty) {
        final deviceId = deviceList.first.toString();
        stdout.writeln('\nDevice found: $deviceId — testing mirroring...\n');

        await _callTool(client, 'start_mirroring', {'device_id': deviceId});
        await _callTool(client, 'inject_key', {'keycode': 3}); // Home
        await _callTool(client, 'inject_key', {'keycode': 4}); // Back
        await _callTool(client, 'inject_touch', {
          'x': 540,
          'y': 960,
          'width': 1080,
          'height': 1920,
        });
        await _callTool(client, 'inject_text', {'text': 'hello from MCP'});
        await _callTool(client, 'inject_scroll', {
          'x': 540,
          'y': 960,
          'width': 1080,
          'height': 1920,
          'hScroll': 0,
          'vScroll': -3,
        });
        await _callTool(client, 'stop_mirroring');
      }
    } else {
      stdout.writeln('No devices connected — skipping mirroring tests.\n');
    }

    // --- Resources ---
    await _listResources(client);
    await _readResource(client, 'device://list');
    await _readResource(client, 'mirroring://status');

    // --- Prompts ---
    await _listPrompts(client);
    await _getPrompt(client, 'control_device');
    await _getPrompt(client, 'troubleshoot', {'issue': 'no devices found'});

    stdout.writeln('\n=== All tests passed ===');
  } on Exception catch (e, st) {
    stderr.writeln('Error: $e\n$st');
    exitCode = 1;
  } finally {
    await client.close();
  }
}

Future<void> _listTools(McpClient client) async {
  stdout.writeln('--- Tools ---');
  final result = await client.listTools();
  for (final tool in result.tools) {
    stdout.writeln('  ${tool.name}: ${tool.description}');
  }
  stdout.writeln();
}

Future<void> _callTool(
  McpClient client,
  String name, [
  Map<String, dynamic>? arguments,
]) async {
  stdout.writeln('>> call $name${arguments != null ? " $arguments" : ""}');
  final result = await client.callTool(
    CallToolRequest(name: name, arguments: arguments ?? {}),
  );
  if (result.isError) {
    stdout.writeln('   ERROR: ${_textOf(result)}');
  } else {
    stdout.writeln('   ${_textOf(result)}');
  }
}

Future<void> _listResources(McpClient client) async {
  stdout.writeln('\n--- Resources ---');
  final result = await client.listResources();
  for (final r in result.resources) {
    stdout.writeln('  ${r.uri}: ${r.description}');
  }
  stdout.writeln();
}

Future<void> _readResource(McpClient client, String uri) async {
  stdout.writeln('>> read $uri');
  final result = await client.readResource(ReadResourceRequest(uri: uri));
  for (final part in result.contents) {
    if (part is TextResourceContents) {
      stdout.writeln('   ${part.text}');
    }
  }
}

Future<void> _listPrompts(McpClient client) async {
  stdout.writeln('\n--- Prompts ---');
  final result = await client.listPrompts();
  for (final p in result.prompts) {
    stdout.writeln('  ${p.name}: ${p.description}');
  }
  stdout.writeln();
}

Future<void> _getPrompt(
  McpClient client,
  String name, [
  Map<String, String>? arguments,
]) async {
  stdout.writeln('>> prompt $name${arguments != null ? " $arguments" : ""}');
  final result = await client.getPrompt(
    GetPromptRequest(name: name, arguments: arguments),
  );
  for (final msg in result.messages) {
    final content = msg.content;
    final text = content is TextContent
        ? content.text
        : '[${content.runtimeType}]';
    stdout.writeln('   [${msg.role}] $text');
  }
}

String? _textOf(CallToolResult result) {
  for (final c in result.content) {
    if (c is TextContent) return c.text;
  }
  return null;
}

/// Finds the fvm executable, checking PATH first, then common locations.
String? _findFvm() {
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(':')) {
    final candidate = '$dir/fvm';
    if (File(candidate).existsSync()) return candidate;
  }
  const homebrew = '/opt/homebrew/bin/fvm';
  if (File(homebrew).existsSync()) return homebrew;
  return null;
}
