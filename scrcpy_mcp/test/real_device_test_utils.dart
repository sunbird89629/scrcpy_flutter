// Shared test utilities for real-device integration tests.
//
// This is a plain library (not a test file), so dart test skips it.
// Import it from individual *_real_device_*_test.dart files.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_adapters.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

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
  String? get proxyUrl => _connected ? 'http://127.0.0.1:27183/live' : null;

  @override
  String? get playerUrl => _connected
      ? 'http://127.0.0.1:27184/index.html?ws=ws://127.0.0.1:27184/ws'
      : null;

  @override
  Future<void> start(String deviceId) async => _connected = true;

  @override
  Future<void> stop() async => _connected = false;

  @override
  void sendControlMessage(ScrcpyControlMessage message) {}

  @override
  void injectText(String text) {}
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
/// Returns the connected client. Call [close] to tear down the stream pair.
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
