import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/src/mcp_http_server.dart';
import 'package:scrcpy_mcp/src/recording_adb.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

// ---------------------------------------------------------------------------
// Mock ADB
// ---------------------------------------------------------------------------

class MockAdb implements ScrcpyAdb {
  MockAdb({List<String>? devices}) : _devices = devices ?? ['device1'];
  final List<String> _devices;

  @override
  String get adbPath => 'adb';

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
  Future<Uint8List> takeScreenshot(String deviceId) async =>
      // minimal 1x1 transparent PNG (67 bytes)
      Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0A,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9C,
        0x62,
        0x00,
        0x01,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x0D,
        0x0A,
        0x2D,
        0xB4,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);
}

// ---------------------------------------------------------------------------
// Mock ScrcpyViewController
// ---------------------------------------------------------------------------

class MockScrcpyViewController extends ScrcpyViewController {
  MockScrcpyViewController() : super(adb: MockAdb());

  bool _fakeConnected = false;

  @override
  bool get isConnected => _fakeConnected;

  @override
  bool get isActive => _fakeConnected;

  @override
  ScrcpyServer? get server => null;

  @override
  Future<void> start(
    String deviceId, {
    ScrcpyLogger? logger,
    VoidCallback? onStarted,
    VoidCallback? onStopped,
    ValueChanged<String>? onError,
  }) async {
    _fakeConnected = true;
    onStarted?.call();
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _fakeConnected = false;
    notifyListeners();
  }

  @override
  void sendControlMessage(ScrcpyControlMessage message) {}

  @override
  void injectKey(int keycode, {int metastate = 0}) {}

  @override
  void injectText(String text) {}
}

// ---------------------------------------------------------------------------
// In-memory test harness
// ---------------------------------------------------------------------------

class _TestEnv {
  _TestEnv({List<String>? devices})
      : adb = MockAdb(devices: devices ?? ['device1']),
        viewController = MockScrcpyViewController() {
    server = ScrcpyMcpServer(session: viewController, adb: adb);
  }

  final MockAdb adb;
  final MockScrcpyViewController viewController;
  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async {
    final serverToClient = StreamController<List<int>>();
    final clientToServer = StreamController<List<int>>();

    final serverTransport = IOStreamTransport(
      stream: clientToServer.stream,
      sink: serverToClient.sink,
    );
    final clientTransport = IOStreamTransport(
      stream: serverToClient.stream,
      sink: clientToServer.sink,
    );

    await server.mcpServer.connect(serverTransport);

    client = McpClient(
      const Implementation(name: 'test-client', version: '0.0.1'),
      options: const McpClientOptions(capabilities: ClientCapabilities()),
    );
    await client.connect(clientTransport);

    addTearDown(() async {
      await serverToClient.close();
      await clientToServer.close();
      viewController.dispose();
    });
  }
}

// ---------------------------------------------------------------------------
// Recording mocks + env
// ---------------------------------------------------------------------------

class _MockRecordingAdb implements RecordingAdb {
  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    return _FakeRecordingProcess();
  }

  @override
  Future<void> pullFile(
    String deviceId,
    String remotePath,
    String localPath,
  ) async {
    // Write a minimal file so File(localPath).length() succeeds in _stopRecording.
    await File(localPath).writeAsBytes([0]);
  }

  @override
  Future<void> removeFile(String deviceId, String remotePath) async {}
}

class _FakeRecordingProcess implements RecordingProcess {
  final _completer = Completer<int>();

  @override
  Future<int> get exitCode => _completer.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_completer.isCompleted) _completer.complete(0);
    return true;
  }
}

class _RecordingTestEnv {
  _RecordingTestEnv({List<String>? devices})
      : adb = MockAdb(devices: devices ?? ['device1']),
        recordingAdb = _MockRecordingAdb(),
        viewController = MockScrcpyViewController() {
    server = ScrcpyMcpServer(
      session: viewController,
      adb: adb,
      recordingAdb: recordingAdb,
    );
  }

  final MockAdb adb;
  final _MockRecordingAdb recordingAdb;
  final MockScrcpyViewController viewController;
  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async {
    final serverToClient = StreamController<List<int>>();
    final clientToServer = StreamController<List<int>>();

    final serverTransport = IOStreamTransport(
      stream: clientToServer.stream,
      sink: serverToClient.sink,
    );
    final clientTransport = IOStreamTransport(
      stream: serverToClient.stream,
      sink: clientToServer.sink,
    );

    await server.mcpServer.connect(serverTransport);

    client = McpClient(
      const Implementation(name: 'test-client', version: '0.0.1'),
      options: const McpClientOptions(capabilities: ClientCapabilities()),
    );
    await client.connect(clientTransport);

    addTearDown(() async {
      await serverToClient.close();
      await clientToServer.close();
      viewController.dispose();
    });
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _text(CallToolResult r) => (r.content.first as TextContent).text;
String _resourceText(ReadResourceResult r) =>
    (r.contents.first as TextResourceContents).text;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ScrcpyMcpServer — initialization', () {
    test('advertises 8 tools after connect', () async {
      final env = _TestEnv();
      await env.connect();

      final tools = await env.client.listTools();
      final names = tools.tools.map((t) => t.name).toSet();

      expect(
        names,
        containsAll([
          'list_devices',
          'start_mirroring',
          'stop_mirroring',
          'inject_key',
          'inject_touch',
          'inject_text',
          'inject_scroll',
          'take_screenshot',
        ]),
      );
    });

    test('advertises 2 resources', () async {
      final env = _TestEnv();
      await env.connect();

      final resources = await env.client.listResources();
      final uris = resources.resources.map((r) => r.uri).toSet();

      expect(uris, containsAll(['device://list', 'mirroring://status']));
    });

    test('advertises 2 prompts', () async {
      final env = _TestEnv();
      await env.connect();

      final prompts = await env.client.listPrompts();
      final names = prompts.prompts.map((p) => p.name).toSet();

      expect(names, containsAll(['control_device', 'troubleshoot']));
    });
  });

  group('ScrcpyMcpServer — tools', () {
    test('list_devices returns JSON array of device serials', () async {
      final env = _TestEnv(devices: ['emulator-5554', 'R3CN12345']);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'list_devices'),
      );

      expect(result.isError, isFalse);
      final devices = jsonDecode(_text(result)) as List;
      expect(devices, containsAll(['emulator-5554', 'R3CN12345']));
    });

    test('list_devices returns empty array when no devices', () async {
      final env = _TestEnv(devices: []);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'list_devices'),
      );

      expect(result.isError, isFalse);
      expect(jsonDecode(_text(result)), isEmpty);
    });

    test('stop_mirroring without active session returns informational message',
        () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'stop_mirroring'),
      );

      expect(result.isError, isFalse);
      expect(_text(result), contains('No active'));
    });

    test('inject_key without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'inject_key',
          arguments: {'keycode': 3},
        ),
      );

      expect(result.isError, isTrue);
    });

    test('inject_touch without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'inject_touch',
          arguments: {'x': 100, 'y': 200, 'width': 1080, 'height': 1920},
        ),
      );

      expect(result.isError, isTrue);
    });

    test('inject_text without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'inject_text',
          arguments: {'text': 'hello'},
        ),
      );

      expect(result.isError, isTrue);
    });

    test('inject_scroll without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'inject_scroll',
          arguments: {
            'x': 540,
            'y': 960,
            'width': 1080,
            'height': 1920,
            'hScroll': 0,
            'vScroll': -3,
          },
        ),
      );

      expect(result.isError, isTrue);
    });

    test('take_screenshot with connected device returns ImageContent',
        () async {
      final env = _TestEnv(devices: ['emulator-5554']);
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': 'emulator-5554'},
        ),
      );

      final result = await env.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      );

      expect(result.isError, isFalse);
      expect(result.content.first, isA<ImageContent>());
      final img = result.content.first as ImageContent;
      expect(img.mimeType, 'image/png');
      expect(img.data, isNotEmpty);
    });

    test('take_screenshot without devices returns error', () async {
      final env = _TestEnv(devices: []);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      );

      expect(result.isError, isTrue);
    });
  });

  group('ScrcpyMcpServer — resources', () {
    test('device://list returns JSON array matching mock devices', () async {
      final env = _TestEnv(devices: ['emulator-5554']);
      await env.connect();

      final result = await env.client.readResource(
        const ReadResourceRequest(uri: 'device://list'),
      );

      final devices = jsonDecode(_resourceText(result)) as List;
      expect(devices, ['emulator-5554']);
    });

    test('mirroring://status shows inactive when no session started', () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.readResource(
        const ReadResourceRequest(uri: 'mirroring://status'),
      );

      final status = jsonDecode(_resourceText(result)) as Map;
      expect(status['active'], isFalse);
      expect(status.containsKey('device_id'), isFalse);
    });
  });

  group('ScrcpyMcpServer — prompts', () {
    test('control_device prompt lists available devices', () async {
      final env = _TestEnv(devices: ['emulator-5554', 'pixel-8']);
      await env.connect();

      final result = await env.client.getPrompt(
        const GetPromptRequest(name: 'control_device'),
      );

      final text = (result.messages.first.content as TextContent).text;
      expect(text, contains('emulator-5554'));
      expect(text, contains('pixel-8'));
    });

    test('control_device prompt with device_id argument targets that device',
        () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.getPrompt(
        const GetPromptRequest(
          name: 'control_device',
          arguments: {'device_id': 'specific-device'},
        ),
      );

      final text = (result.messages.first.content as TextContent).text;
      expect(text, contains('specific-device'));
    });

    test('troubleshoot prompt mentions no-devices when list is empty',
        () async {
      final env = _TestEnv(devices: []);
      await env.connect();

      final result = await env.client.getPrompt(
        const GetPromptRequest(name: 'troubleshoot'),
      );

      final text = (result.messages.first.content as TextContent).text;
      expect(text, contains('none'));
    });

    test('troubleshoot prompt includes reported issue in message', () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.getPrompt(
        const GetPromptRequest(
          name: 'troubleshoot',
          arguments: {'issue': 'black screen after unlock'},
        ),
      );

      final text = (result.messages.first.content as TextContent).text;
      expect(text, contains('black screen after unlock'));
    });
  });

  group('McpHttpServer — lifecycle', () {
    test('starts and stops cleanly on a local port', () async {
      final adb = MockAdb();
      final vc = MockScrcpyViewController();
      addTearDown(vc.dispose);

      final httpServer = McpHttpServer();

      expect(httpServer.serverUrl, isNull);

      await httpServer.start(port: 19817, session: vc, adb: adb);
      expect(httpServer.serverUrl, 'http://localhost:19817/mcp');

      await httpServer.stop();
      expect(httpServer.serverUrl, isNull);
    });
  });

  group('ScrcpyMcpServer — recording', () {
    test('advertises start_recording and stop_recording when enabled',
        () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final tools = await env.client.listTools();
      final names = tools.tools.map((t) => t.name).toSet();

      expect(names, contains('start_recording'));
      expect(names, contains('stop_recording'));
    });

    test('advertises recording://status resource when enabled', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final resources = await env.client.listResources();
      final uris = resources.resources.map((r) => r.uri).toSet();

      expect(uris, contains('recording://status'));
    });

    test('start_recording without active mirroring returns error', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      expect(result.isError, isTrue);
      expect(_text(result), contains('No active mirroring session'));
    });

    test('start_recording while already recording returns error', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      await env.client.callTool(
        const CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': 'device1'},
        ),
      );
      await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      final result = await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      expect(result.isError, isTrue);
      expect(_text(result), contains('Already recording'));
    });

    test('stop_recording when not recording returns friendly message',
        () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'stop_recording'),
      );

      expect(result.isError, isFalse);
      expect(_text(result), contains('No active recording'));
    });

    test('recording://status is idle when not recording', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final result = await env.client.readResource(
        const ReadResourceRequest(uri: 'recording://status'),
      );

      final json = jsonDecode(_resourceText(result)) as Map<String, dynamic>;
      expect(json['is_recording'], isFalse);
    });

    test('recording://status reflects active recording', () async {
      final env = _RecordingTestEnv();
      await env.connect();

      await env.client.callTool(
        const CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': 'device1'},
        ),
      );
      await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      final result = await env.client.readResource(
        const ReadResourceRequest(uri: 'recording://status'),
      );
      final json = jsonDecode(_resourceText(result)) as Map<String, dynamic>;

      expect(json['is_recording'], isTrue);
      expect(json['device_id'], 'device1');
    });
  });
}
