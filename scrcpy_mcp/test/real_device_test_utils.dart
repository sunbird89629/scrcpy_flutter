// Shared test utilities for real-device integration tests.
//
// This is a plain library (not a test file), so dart test skips it.
// Import it from individual *_real_device_*_test.dart files.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_adapters.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';

// ---------------------------------------------------------------------------
// Mock ADB — minimal implementation for unit tests
// ---------------------------------------------------------------------------

class MockAdb implements ScrcpyAdb {
  MockAdb({List<String>? devices}) : _devices = devices ?? ['device1'];
  final List<String> _devices;

  @override
  Future<List<String>> getDevices() async => List.unmodifiable(_devices);

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      ProcessResult(0, 0, '', '');

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {}

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {}

  @override
  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) async {}

  @override
  Future<Process> startProcess(List<String> arguments) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async =>
      // minimal 1x1 transparent PNG (67 bytes)
      Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
        0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62,
        0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
        0x82,
      ]);
}

// ---------------------------------------------------------------------------
// Mock session — keeps session "alive" without real scrcpy
// ---------------------------------------------------------------------------

class MockScrcpySession implements ScrcpySession {
  bool _connected = false;

  @override
  int? get videoWidth => _connected ? 1080 : null;

  @override
  int? get videoHeight => _connected ? 1920 : null;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> start(String deviceId) async => _connected = true;

  @override
  Future<void> stop() async => _connected = false;

  @override
  void sendControlMessage(ScrcpyControlMessage message) {}

  @override
  void injectText(String text) {}

  @override
  Stream<ScrcpyDeviceMessage> get deviceMessages =>
      const Stream<ScrcpyDeviceMessage>.empty();

  @override
  Future<String> getClipboard({
    Duration timeout = const Duration(seconds: 5),
  }) =>
      Future.value('');
}

// ---------------------------------------------------------------------------
// Test environment — real ADB adapter, mock session, in-memory MCP transport
// ---------------------------------------------------------------------------

class RealDeviceEnv {
  RealDeviceEnv({
    required this.adb,
    MockScrcpySession? session,
    this.enableRecording = false,
  }) : _session = session ?? MockScrcpySession() {
    server = ScrcpyMcpServer(
      session: _session,
      adb: adb,
      recordingAdb: enableRecording ? adb : null,
    );
  }

  final ScrcpyMcpAdb adb;
  final bool enableRecording;
  final MockScrcpySession _session;
  late final ScrcpyMcpServer server;
  late McpClient client;

  bool get sessionConnected => _session.isConnected;

  Future<void> connect() async {
    client = (await connectMcpPair(server)).$1;
  }
}

// ---------------------------------------------------------------------------
// E2E environment — real ScrcpySessionImpl, real ADB, in-memory MCP transport
// ---------------------------------------------------------------------------

class RealDeviceE2eEnv {
  RealDeviceE2eEnv({required this.adb, required ScrcpySession session}) {
    server = ScrcpyMcpServer(session: session, adb: adb);
  }

  final ScrcpyMcpAdb adb;
  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async {
    client = (await connectMcpPair(server)).$1;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wires an in-memory MCP transport between [server] and a new [McpClient].
///
/// Returns the connected client. Call the returned `close` function to tear
/// down the stream pair.
// ignore: comment_references
Future<(McpClient client, Future<void> Function() close)> connectMcpPair(
  ScrcpyMcpServer server,
) async {
  final serverToClient = StreamController<List<int>>();
  final clientToServer = StreamController<List<int>>();

  await server.mcpServer.connect(
    IOStreamTransport(
      stream: clientToServer.stream,
      sink: serverToClient.sink,
    ),
  );

  final client = McpClient(
    const Implementation(name: 'test-client', version: '0.0.1'),
    options: const McpClientOptions(capabilities: ClientCapabilities()),
  );
  await client.connect(
    IOStreamTransport(
      stream: serverToClient.stream,
      sink: clientToServer.sink,
    ),
  );

  Future<void> close() async {
    await serverToClient.close();
    await clientToServer.close();
  }

  return (client, close);
}

String textContent(CallToolResult r) => (r.content.first as TextContent).text;

Uint8List screenshotBytes(CallToolResult r) =>
    base64Decode((r.content.first as ImageContent).data);

bool hasScreenChanged(
  Uint8List before,
  Uint8List after, {
  int threshold = 100,
}) {
  if (before.length != after.length) return true;
  var diff = 0;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i] && ++diff > threshold) return true;
  }
  return false;
}

Future<(int, int)> getScreenSize(ScrcpyMcpAdb adb, String deviceId) async {
  final result = await adb.shell(['wm', 'size'], deviceId: deviceId);
  final m = RegExp(r'(\d+)x(\d+)').firstMatch(result.stdout as String);
  if (m == null) return (1080, 1920);
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}
