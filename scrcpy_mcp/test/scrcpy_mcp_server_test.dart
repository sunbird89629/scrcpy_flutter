import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/src/mcp_http_server.dart';
import 'package:scrcpy_mcp/src/recording_adb.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_core.dart';
import 'package:test/test.dart';

import 'real_device_test_utils.dart' show connectMcpPair, textContent;

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
// Mock ScrcpySession
// ---------------------------------------------------------------------------

class MockScrcpySession implements ScrcpySession {
  bool _fakeConnected = false;
  final List<ScrcpyControlMessage> sentMessages = [];

  @override
  int? get videoWidth => _fakeConnected ? 1080 : null;

  @override
  int? get videoHeight => _fakeConnected ? 1920 : null;

  @override
  bool get isConnected => _fakeConnected;

  @override
  String? get proxyUrl =>
      _fakeConnected ? 'http://127.0.0.1:27183/live' : null;

  @override
  String? get playerUrl => _fakeConnected
      ? 'http://127.0.0.1:27184/index.html?ws=ws://127.0.0.1:27184/ws'
      : null;

  @override
  Future<void> start(String deviceId) async {
    _fakeConnected = true;
  }

  @override
  Future<void> stop() async {
    _fakeConnected = false;
  }

  @override
  void sendControlMessage(ScrcpyControlMessage message) {
    sentMessages.add(message);
  }

  @override
  void injectText(String text) {}
}

// ---------------------------------------------------------------------------
// In-memory test harness
// ---------------------------------------------------------------------------

class _TestEnv {
  _TestEnv({List<String>? devices})
      : adb = MockAdb(devices: devices ?? ['device1']),
        session = MockScrcpySession() {
    server = ScrcpyMcpServer(session: session, adb: adb);
  }

  final MockAdb adb;
  final MockScrcpySession session;
  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async {
    final (c, close) = await connectMcpPair(server);
    client = c;
    addTearDown(close);
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
        session = MockScrcpySession() {
    server = ScrcpyMcpServer(
      session: session,
      adb: adb,
      recordingAdb: recordingAdb,
    );
  }

  final MockAdb adb;
  final _MockRecordingAdb recordingAdb;
  final MockScrcpySession session;
  late final ScrcpyMcpServer server;
  late McpClient client;

  Future<void> connect() async {
    final (c, close) = await connectMcpPair(server);
    client = c;
    addTearDown(close);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _resourceText(ReadResourceResult r) =>
    (r.contents.first as TextResourceContents).text;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ScrcpyMcpServer — initialization', () {
    test('advertises 9 tools after connect', () async {
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
          'inject_swipe',
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
      final devices = jsonDecode(textContent(result)) as List;
      expect(devices, containsAll(['emulator-5554', 'R3CN12345']));
    });

    test('list_devices returns empty array when no devices', () async {
      final env = _TestEnv(devices: []);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'list_devices'),
      );

      expect(result.isError, isFalse);
      expect(jsonDecode(textContent(result)), isEmpty);
    });

    test('stop_mirroring without active session returns informational message',
        () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'stop_mirroring'),
      );

      expect(result.isError, isFalse);
      expect(textContent(result), contains('No active'));
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

    test('inject_swipe without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'inject_swipe',
          arguments: {
            'x1': 540,
            'y1': 1500,
            'x2': 540,
            'y2': 500,
            'width': 1080,
            'height': 1920,
          },
        ),
      );

      expect(result.isError, isTrue);
    });

    test('inject_swipe sends DOWN + steps×MOVE + UP with interpolated coords',
        () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': 'device1'},
        ),
      );
      env.session.sentMessages.clear();

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'inject_swipe',
          arguments: {
            'x1': 100,
            'y1': 1000,
            'x2': 100,
            'y2': 200,
            'width': 1080,
            'height': 1920,
            'durationMs': 50,
            'steps': 4,
          },
        ),
      );

      expect(result.isError, isFalse, reason: textContent(result));

      final touches = env.session.sentMessages
          .whereType<ScrcpyInjectTouchMessage>()
          .toList();
      expect(touches, hasLength(6), reason: '1 DOWN + 4 MOVE + 1 UP');

      expect(touches.first.action, ScrcpyAction.down);
      expect((touches.first.x, touches.first.y), (100, 1000));

      expect(touches.last.action, ScrcpyAction.up);
      expect((touches.last.x, touches.last.y), (100, 200));

      // Interpolated MOVE coords: y goes 1000 → 800 → 600 → 400 → 200.
      final moves = touches.sublist(1, 5);
      expect(moves.every((m) => m.action == ScrcpyAction.move), isTrue);
      expect(moves.map((m) => m.y).toList(), [800, 600, 400, 200]);
      expect(moves.every((m) => m.x == 100), isTrue);
    });

    test('inject_swipe with steps=0 returns error', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': 'device1'},
        ),
      );

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'inject_swipe',
          arguments: {
            'x1': 0,
            'y1': 0,
            'x2': 100,
            'y2': 100,
            'width': 1080,
            'height': 1920,
            'steps': 0,
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(textContent(result), contains('steps'));
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
      final session = MockScrcpySession();

      final httpServer = McpHttpServer();

      expect(httpServer.serverUrl, isNull);

      await httpServer.start(port: 19817, session: session, adb: adb);
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
      expect(textContent(result), contains('No active mirroring session'));
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
      expect(textContent(result), contains('Already recording'));
    });

    test('stop_recording when not recording returns friendly message',
        () async {
      final env = _RecordingTestEnv();
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'stop_recording'),
      );

      expect(result.isError, isFalse);
      expect(textContent(result), contains('No active recording'));
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
