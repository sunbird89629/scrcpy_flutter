import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:stream_channel/stream_channel.dart';

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
  }) async => ProcessResult(0, 0, '', '');

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
}

// ---------------------------------------------------------------------------
// In-memory client+server harness (mirrors dart_mcp's TestEnvironment)
// ---------------------------------------------------------------------------

base class _TestMcpClient extends MCPClient {
  _TestMcpClient()
      : super(Implementation(name: 'test-client', version: '0.0.1'));
}

class _TestEnv {
  final _clientCtrl = StreamController<String>();
  final _serverCtrl = StreamController<String>();

  late final _clientChannel = StreamChannel<String>.withCloseGuarantee(
    _serverCtrl.stream,
    _clientCtrl.sink,
  );
  late final _serverChannel = StreamChannel<String>.withCloseGuarantee(
    _clientCtrl.stream,
    _serverCtrl.sink,
  );

  final _TestMcpClient client;
  late final ScrcpyMcpServer server;
  late final ServerConnection conn;

  _TestEnv(MockAdb adb) : client = _TestMcpClient() {
    server = ScrcpyMcpServer(_serverChannel, adb: adb);
    conn = client.connectServer(_clientChannel);
    addTearDown(_shutdown);
  }

  Future<InitializeResult> init() async {
    final result = await conn.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    if (result.protocolVersion?.isSupported ?? false) {
      conn.notifyInitialized(InitializedNotification());
      await server.initialized;
    }
    return result;
  }

  Future<void> _shutdown() async {
    await client.shutdown();
    await server.shutdown();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _text(CallToolResult r) => (r.content.single as TextContent).text;

String _resourceText(ReadResourceResult r) =>
    (r.contents.single as TextResourceContents).text;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ScrcpyMcpServer — initialization', () {
    test('advertises tools, resources, and prompts capabilities', () async {
      final env = _TestEnv(MockAdb());
      final result = await env.init();

      expect(result.capabilities.tools, isNotNull);
      expect(result.capabilities.resources, isNotNull);
      expect(result.capabilities.prompts, isNotNull);
    });

    test('lists 7 tools after initialize', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final tools = await env.conn.listTools();
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
        ]),
      );
    });

    test('lists 2 resources after initialize', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final resources = await env.conn.listResources();
      final uris = resources.resources.map((r) => r.uri).toSet();

      expect(uris, containsAll(['device://list', 'mirroring://status']));
    });

    test('lists 2 prompts after initialize', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final prompts = await env.conn.listPrompts();
      final names = prompts.prompts.map((p) => p.name).toSet();

      expect(names, containsAll(['control_device', 'troubleshoot']));
    });
  });

  group('ScrcpyMcpServer — tools', () {
    test('list_devices returns JSON array of device serials', () async {
      final env = _TestEnv(MockAdb(devices: ['emulator-5554', 'R3CN12345']));
      await env.init();

      final result = await env.conn.callTool(
        CallToolRequest(name: 'list_devices'),
      );

      expect(result.isError, isNot(true));
      final devices = jsonDecode(_text(result)) as List;
      expect(devices, containsAll(['emulator-5554', 'R3CN12345']));
    });

    test('list_devices returns empty array when no devices', () async {
      final env = _TestEnv(MockAdb(devices: []));
      await env.init();

      final result = await env.conn.callTool(
        CallToolRequest(name: 'list_devices'),
      );

      expect(result.isError, isNot(true));
      expect(jsonDecode(_text(result)), isEmpty);
    });

    test('stop_mirroring without active session returns informational message',
        () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.callTool(
        CallToolRequest(name: 'stop_mirroring'),
      );

      expect(result.isError, isNot(true));
      expect(_text(result), contains('No active'));
    });

    test('inject_key without active session returns error', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.callTool(
        CallToolRequest(name: 'inject_key', arguments: {'keycode': 3}),
      );

      expect(result.isError, isTrue);
    });

    test('inject_touch without active session returns error', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.callTool(
        CallToolRequest(
          name: 'inject_touch',
          arguments: {'x': 100, 'y': 200, 'width': 1080, 'height': 1920},
        ),
      );

      expect(result.isError, isTrue);
    });

    test('inject_text without active session returns error', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.callTool(
        CallToolRequest(
          name: 'inject_text',
          arguments: {'text': 'hello'},
        ),
      );

      expect(result.isError, isTrue);
    });

    test('inject_scroll without active session returns error', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.callTool(
        CallToolRequest(
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

    test('inject_key rejects missing required argument', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.callTool(
        CallToolRequest(name: 'inject_key', arguments: {}),
      );

      expect(result.isError, isTrue);
    });
  });

  group('ScrcpyMcpServer — resources', () {
    test('device://list returns JSON array matching mock devices', () async {
      final env = _TestEnv(MockAdb(devices: ['emulator-5554']));
      await env.init();

      final result = await env.conn.readResource(
        ReadResourceRequest(uri: 'device://list'),
      );

      final devices = jsonDecode(_resourceText(result)) as List;
      expect(devices, ['emulator-5554']);
    });

    test('mirroring://status shows inactive when no session started', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.readResource(
        ReadResourceRequest(uri: 'mirroring://status'),
      );

      final status = jsonDecode(_resourceText(result)) as Map;
      expect(status['active'], isFalse);
      expect(status.containsKey('device_id'), isFalse);
    });
  });

  group('ScrcpyMcpServer — prompts', () {
    test('control_device prompt lists available devices', () async {
      final env = _TestEnv(MockAdb(devices: ['emulator-5554', 'pixel-8']));
      await env.init();

      final result = await env.conn.getPrompt(
        GetPromptRequest(name: 'control_device'),
      );

      final text = (result.messages.single.content as TextContent).text;
      expect(text, contains('emulator-5554'));
      expect(text, contains('pixel-8'));
    });

    test('control_device prompt with device_id argument targets that device',
        () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.getPrompt(
        GetPromptRequest(
          name: 'control_device',
          arguments: {'device_id': 'specific-device'},
        ),
      );

      final text = (result.messages.single.content as TextContent).text;
      expect(text, contains('specific-device'));
    });

    test('troubleshoot prompt mentions no-devices when list is empty',
        () async {
      final env = _TestEnv(MockAdb(devices: []));
      await env.init();

      final result = await env.conn.getPrompt(
        GetPromptRequest(name: 'troubleshoot'),
      );

      final text = (result.messages.single.content as TextContent).text;
      expect(text, contains('none'));
    });

    test('troubleshoot prompt includes reported issue in message', () async {
      final env = _TestEnv(MockAdb());
      await env.init();

      final result = await env.conn.getPrompt(
        GetPromptRequest(
          name: 'troubleshoot',
          arguments: {'issue': 'black screen after unlock'},
        ),
      );

      final text = (result.messages.single.content as TextContent).text;
      expect(text, contains('black screen after unlock'));
    });
  });
}
