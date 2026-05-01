#!/usr/bin/env dart
// Test client for scrcpy_mcp — exercises all MCP capabilities.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';

void main(List<String> args) async {
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

  // Start the server subprocess via `fvm dart run`.
  final process = await Process.start(fvmExe, [
    'dart',
    'run',
    serverPath,
    ...adbArgs,
  ]);

  // Forward server stderr to our stderr for diagnostics.
  process.stderr.transform(utf8.decoder).listen(stderr.write);

  final client = MCPClient(
    Implementation(name: 'scrcpy-mcp-test', version: '0.1.0'),
  );

  final server = client.connectServer(
    stdioChannel(input: process.stdout, output: process.stdin),
  );
  unawaited(server.done.then((_) => process.kill()));

  try {
    // --- Initialize ---
    final initResult = await server.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    server.notifyInitialized();

    stdout
      ..writeln('Server: ${initResult.serverInfo.name} '
          'v${initResult.serverInfo.version}')
      ..writeln('Protocol: ${initResult.protocolVersion}')
      ..writeln('Instructions: ${initResult.instructions}\n');

    // --- Tools ---
    await _listTools(server);
    await _callTool(server, 'list_devices');

    // Try mirroring if devices are available.
    final devicesResult = await server.callTool(
      CallToolRequest(name: 'list_devices'),
    );
    final devices = _textOf(devicesResult) ?? '[]';
    if (devices != '[]') {
      final deviceList = jsonDecode(devices) as List;
      if (deviceList.isNotEmpty) {
        final deviceId = deviceList.first.toString();
        stdout.writeln('\nDevice found: $deviceId — testing mirroring...\n');

        await _callTool(server, 'start_mirroring', {'device_id': deviceId});
        await _callTool(server, 'inject_key', {'keycode': 3}); // Home
        await _callTool(server, 'inject_key', {'keycode': 4}); // Back
        await _callTool(server, 'inject_touch', {
          'x': 540,
          'y': 960,
          'width': 1080,
          'height': 1920,
        });
        await _callTool(server, 'inject_text', {'text': 'hello from MCP'});
        await _callTool(server, 'inject_scroll', {
          'x': 540,
          'y': 960,
          'width': 1080,
          'height': 1920,
          'hScroll': 0,
          'vScroll': -3,
        });
        await _callTool(server, 'stop_mirroring');
      }
    } else {
      stdout.writeln('No devices connected — skipping mirroring tests.\n');
    }

    // --- Resources ---
    await _listResources(server);
    await _readResource(server, 'device://list');
    await _readResource(server, 'mirroring://status');

    // --- Prompts ---
    await _listPrompts(server);
    await _getPrompt(server, 'control_device');
    await _getPrompt(server, 'troubleshoot', {'issue': 'no devices found'});

    stdout.writeln('\n=== All tests passed ===');
  } on Exception catch (e, st) {
    stderr.writeln('Error: $e\n$st');
    exitCode = 1;
  } finally {
    await server.shutdown();
    await client.shutdown();
  }
}

Future<void> _listTools(ServerConnection server) async {
  stdout.writeln('--- Tools ---');
  final result = await server.listTools();
  for (final tool in result.tools) {
    stdout.writeln('  ${tool.name}: ${tool.description}');
  }
  stdout.writeln();
}

Future<void> _callTool(
  ServerConnection server,
  String name, [
  Map<String, Object?>? arguments,
]) async {
  stdout.writeln('>> call $name${arguments != null ? " $arguments" : ""}');
  final result = await server.callTool(
    CallToolRequest(name: name, arguments: arguments),
  );
  if (result.isError ?? false) {
    stdout.writeln('   ERROR: ${_textOf(result)}');
  } else {
    stdout.writeln('   ${_textOf(result)}');
  }
}

Future<void> _listResources(ServerConnection server) async {
  stdout.writeln('\n--- Resources ---');
  final result = await server.listResources();
  for (final r in result.resources) {
    stdout.writeln('  ${r.uri}: ${r.description}');
  }
  stdout.writeln();
}

Future<void> _readResource(ServerConnection server, String uri) async {
  stdout.writeln('>> read $uri');
  final result = await server.readResource(ReadResourceRequest(uri: uri));
  for (final part in result.contents) {
    if (part.isText) {
      stdout.writeln('   ${(part as TextResourceContents).text}');
    }
  }
}

Future<void> _listPrompts(ServerConnection server) async {
  stdout.writeln('\n--- Prompts ---');
  final result = await server.listPrompts();
  for (final p in result.prompts) {
    stdout.writeln('  ${p.name}: ${p.description}');
  }
  stdout.writeln();
}

Future<void> _getPrompt(
  ServerConnection server,
  String name, [
  Map<String, String>? arguments,
]) async {
  stdout.writeln('>> prompt $name${arguments != null ? " $arguments" : ""}');
  final result = await server.getPrompt(
    GetPromptRequest(name: name, arguments: arguments),
  );
  for (final msg in result.messages) {
    stdout.writeln('   [${msg.role}] ${_contentText(msg.content)}');
  }
}

String? _textOf(CallToolResult result) {
  for (final c in result.content) {
    if (c.isText) return (c as TextContent).text;
  }
  return null;
}

String _contentText(Content content) {
  if (content.isText) return (content as TextContent).text;
  return '[${content.type}]';
}

/// Finds the fvm executable, checking PATH first, then common locations.
String? _findFvm() {
  // Check PATH via Platform.environment.
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(':')) {
    final candidate = '$dir/fvm';
    if (File(candidate).existsSync()) return candidate;
  }
  // Common homebrew location.
  const homebrew = '/opt/homebrew/bin/fvm';
  if (File(homebrew).existsSync()) return homebrew;
  return null;
}
