// Real-device integration tests for ScrcpyMcpServer.
//
// These tests require a physical Android device connected via ADB.
// Each test calls markTestSkipped() when no device is found, so the suite
// passes cleanly in CI.
//
// Run manually:
//   dart test test/scrcpy_mcp_real_device_test.dart --tags real-device
//
// @Tags annotation allows selective inclusion/exclusion.
@Tags(['real-device'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb_tools/adb_tools.dart';
import 'package:autoglm_logger/app_logger.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_adapters.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock session — keeps session "alive" without real scrcpy
// ---------------------------------------------------------------------------

class _MockScrcpySession implements ScrcpySession {
  bool _connected = false;

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

class _Env {
  _Env({
    required ScrcpyMcpAdb adb,
    _MockScrcpySession? session,
    bool enableRecording = false,
  }) : _session = session ?? _MockScrcpySession() {
    server = ScrcpyMcpServer(
      session: _session,
      adb: adb,
      recordingAdb: enableRecording ? adb : null,
    );
  }

  final _MockScrcpySession _session;
  late final ScrcpyMcpServer server;
  late McpClient client;

  bool get sessionConnected => _session.isConnected;

  Future<void> connect() async {
    final serverToClient = StreamController<List<int>>();
    final clientToServer = StreamController<List<int>>();

    await server.mcpServer.connect(
      IOStreamTransport(
        stream: clientToServer.stream,
        sink: serverToClient.sink,
      ),
    );

    client = McpClient(
      const Implementation(name: 'test-client', version: '0.0.1'),
      options: const McpClientOptions(capabilities: ClientCapabilities()),
    );
    await client.connect(
      IOStreamTransport(
        stream: serverToClient.stream,
        sink: clientToServer.sink,
      ),
    );

    addTearDown(() async {
      await serverToClient.close();
      await clientToServer.close();
    });
  }
}

// ---------------------------------------------------------------------------
// E2E environment — real ScrcpySessionImpl, real ADB, in-memory MCP transport
// ---------------------------------------------------------------------------

// Used by upcoming e2e inject tests (Tasks 3-6).
// ignore: unused_element
class _E2eEnv {
  _E2eEnv({required ScrcpyMcpAdb adb, required ScrcpySession session}) {
    server = ScrcpyMcpServer(session: session, adb: adb);
  }

  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async {
    final serverToClient = StreamController<List<int>>();
    final clientToServer = StreamController<List<int>>();

    await server.mcpServer.connect(
      IOStreamTransport(
        stream: clientToServer.stream,
        sink: serverToClient.sink,
      ),
    );

    client = McpClient(
      const Implementation(name: 'test-client', version: '0.0.1'),
      options: const McpClientOptions(capabilities: ClientCapabilities()),
    );
    await client.connect(
      IOStreamTransport(
        stream: serverToClient.stream,
        sink: clientToServer.sink,
      ),
    );

    addTearDown(() async {
      await serverToClient.close();
      await clientToServer.close();
    });
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _text(CallToolResult r) => (r.content.first as TextContent).text;

// Used by upcoming e2e inject tests (Tasks 3-6).
// ignore: unused_element
Uint8List _screenshotBytes(CallToolResult r) =>
    base64Decode((r.content.first as ImageContent).data);

// Used by upcoming e2e inject tests (Tasks 3-6).
// ignore: unused_element
bool _hasScreenChanged(
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

// Used by upcoming e2e inject tests (Tasks 3-6).
// ignore: unused_element
Future<(int, int)> _getScreenSize(ScrcpyMcpAdb adb, String deviceId) async {
  final result = await adb.shell(['wm', 'size'], deviceId: deviceId);
  final m = RegExp(r'(\d+)x(\d+)').firstMatch(result.stdout as String);
  if (m == null) return (1080, 1920);
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ScrcpyMcpAdb adb;
  late List<String> realDevices;

  initLogging();

  setUpAll(() async {
    adb = ScrcpyMcpAdb(AdbClientImpl());
    realDevices = await adb.getDevices();
  });

  // ── list_devices ───────────────────────────────────────────────────────────

  group('real device — list_devices', () {
    test('returns the connected device serial', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final env = _Env(adb: adb);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'list_devices'),
      );

      expect(result.isError, isFalse);
      final devices = jsonDecode(_text(result)) as List;
      expect(devices, unorderedEquals(realDevices));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ── take_screenshot ────────────────────────────────────────────────────────

  group('real device — take_screenshot', () {
    test('returns a valid PNG from the first connected device', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final env = _Env(adb: adb);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      );

      expect(result.isError, isFalse);
      final img = result.content.first as ImageContent;
      expect(img.mimeType, 'image/png');

      final bytes = base64Decode(img.data);
      // PNG magic: 89 50 4E 47 0D 0A 1A 0A
      expect(
        bytes.sublist(0, 4),
        equals([0x89, 0x50, 0x4E, 0x47]),
        reason: 'First 4 bytes must be PNG magic',
      );
      expect(bytes.length, greaterThan(64));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('explicit invalid device_id returns error', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final env = _Env(adb: adb);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'take_screenshot',
          arguments: {'device_id': 'invalid-device-serial-xyz'},
        ),
      );

      expect(result.isError, isTrue);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ── recording ──────────────────────────────────────────────────────────────

  group('real device — recording', () {
    late String deviceId;
    late _Env env;
    String? pulledPath;

    setUp(() async {
      if (realDevices.isEmpty) return;
      deviceId = realDevices.first;
      env = _Env(adb: adb, enableRecording: true);
      await env.connect();

      // Activate the mock session so start_recording is allowed
      await env.client.callTool(
        CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': deviceId},
        ),
      );
    });

    tearDown(() async {
      if (pulledPath != null) {
        final f = File(pulledPath!);
        if (f.existsSync()) await f.delete();
        pulledPath = null;
      }
    });

    test('start_recording succeeds and returns device path', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final result = await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );
      addTearDown(() async {
        await env.client.callTool(
          const CallToolRequest(name: 'stop_recording'),
        );
      });

      expect(result.isError, isFalse, reason: _text(result));
      final json = jsonDecode(_text(result)) as Map<String, dynamic>;
      expect(json['status'], 'recording');
      expect(json['path_on_device'], contains('.mp4'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('stop_recording pulls video file to local disk', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      await env.client.callTool(const CallToolRequest(name: 'start_recording'));

      // Record for a short moment so the file is non-empty
      await Future<void>.delayed(const Duration(seconds: 3));

      final stopResult = await env.client.callTool(
        const CallToolRequest(name: 'stop_recording'),
      );

      expect(stopResult.isError, isFalse, reason: _text(stopResult));
      final json = jsonDecode(_text(stopResult)) as Map<String, dynamic>;
      expect(json['status'], 'finished');

      pulledPath = json['local_path'] as String;
      expect(pulledPath, endsWith('.mp4'));

      final file = File(pulledPath!);
      expect(file.existsSync(), isTrue,
          reason: 'File should exist at $pulledPath');
      expect(json['size_bytes'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('double start_recording returns error', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      await env.client.callTool(const CallToolRequest(name: 'start_recording'));
      addTearDown(() async {
        await env.client.callTool(
          const CallToolRequest(name: 'stop_recording'),
        );
      });

      final result = await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      expect(result.isError, isTrue);
      expect(_text(result), contains('Already recording'));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  // ── inject controls (e2e with real scrcpy) ────────────────────────────────

  group('real device — inject controls (e2e)', () {
    late ScrcpySessionImpl e2eSession;
    late _E2eEnv e2eEnv;
    late (int, int) screenSize;

    setUpAll(() async {
      if (realDevices.isEmpty) return;
      final deviceId = realDevices.first;
      e2eSession = await ScrcpySessionImpl.create(adb: adb);
      e2eEnv = _E2eEnv(adb: adb, session: e2eSession);
      await e2eEnv.connect();
      await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': deviceId},
        ),
      );
      screenSize = await _getScreenSize(adb, deviceId);
    });

    tearDownAll(() async {
      if (realDevices.isEmpty) return;
      try {
        await e2eEnv.client.callTool(
          const CallToolRequest(name: 'stop_mirroring'),
        );
      } catch (_) {
        // Transport may already be closed; ignore cleanup errors.
      }
    });

    test('inject_scroll changes screen content', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }
      final (w, h) = screenSize;

      final before = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));

      final scrollResult = await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'inject_scroll',
          arguments: {
            'x': w ~/ 2,
            'y': h ~/ 2,
            'width': w,
            'height': h,
            'hScroll': 0,
            'vScroll': -3,
          },
        ),
      );
      expect(scrollResult.isError, isFalse, reason: _text(scrollResult));

      await Future<void>.delayed(const Duration(milliseconds: 800));

      final after = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));

      expect(
        _hasScreenChanged(before, after),
        isTrue,
        reason: 'Screen should change after scrolling',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('inject_key Home navigates to launcher', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final before = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));

      final keyResult = await e2eEnv.client.callTool(
        const CallToolRequest(
          name: 'inject_key',
          arguments: {'keycode': 3},
        ),
      );
      expect(keyResult.isError, isFalse, reason: _text(keyResult));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      final after = _screenshotBytes(await e2eEnv.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      ));

      expect(
        _hasScreenChanged(before, after),
        isTrue,
        reason: 'Home key should trigger navigation or launcher animation',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
