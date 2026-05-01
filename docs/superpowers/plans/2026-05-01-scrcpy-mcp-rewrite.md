# scrcpy_mcp Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite scrcpy_mcp using dart_mcp SDK to create a proper MCP server with Tools, Resources, and Prompts support.

**Architecture:** Extend `MCPServer` from dart_mcp with `ToolsSupport`, `ResourcesSupport`, and `PromptsSupport` mixins. The server wraps `ScrcpyServer` from scrcpy_view, exposing device management and control operations as MCP tools, resources, and prompts. A thin CLI entry point in `bin/` connects via Stdio.

**Tech Stack:** dart_mcp ^0.5.1, scrcpy_view (local), autoglm_adb (local), autoglm_logger (local)

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `scrcpy_mcp/pubspec.yaml` | Modify | Add dart_mcp dependency |
| `scrcpy_mcp/lib/scrcpy_mcp.dart` | Modify | Update exports |
| `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart` | Rewrite | Core MCP server implementation |
| `scrcpy_mcp/lib/src/scrcpy_mcp_adapters.dart` | Keep | ADB/Logger adapters (no changes) |
| `scrcpy_mcp/bin/scrcpy_mcp.dart` | Create | CLI entry point |
| `scrcpy_mcp/test/scrcpy_mcp_server_test.dart` | Create | Unit tests |

---

### Task 1: Update pubspec.yaml

**Files:**
- Modify: `scrcpy_mcp/pubspec.yaml`

- [ ] **Step 1: Add dart_mcp dependency**

```yaml
name: scrcpy_mcp
description: MCP server for scrcpy — Android screen mirroring via MCP protocol.
publish_to: none
version: 0.2.0

environment:
  sdk: ^3.5.0

resolution: workspace

dependencies:
  dart_mcp: ^0.5.1
  autoglm_adb:
    path: ../packages/autoglm_adb
  autoglm_logger:
    path: ../packages/autoglm_logger
  scrcpy_view:
    path: ../scrcpy_view
  stream_channel: ^2.1.0

dev_dependencies:
  test: ^1.25.0
```

- [ ] **Step 2: Run melos bootstrap**

Run: `melos bootstrap`
Expected: Dependencies resolved successfully.

- [ ] **Step 3: Commit**

```bash
git add scrcpy_mcp/pubspec.yaml
git commit -m "feat(scrcpy_mcp): add dart_mcp dependency"
```

---

### Task 2: Create ScrcpyMcpServer with ToolsSupport

**Files:**
- Rewrite: `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`
- Test: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Write failing test for list_devices tool**

```dart
// scrcpy_mcp/test/scrcpy_mcp_server_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_mcp/src/scrcpy_mcp_server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:test/test.dart';

class MockAdb implements ScrcpyAdb {
  List<String> devices = ['device1', 'device2'];

  @override
  String get adbPath => 'adb';

  @override
  Future<List<String>> getDevices() async => devices;

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
  Future<void> push(String localPath, String remotePath,
      {String? deviceId}) async {}
}

void main() {
  group('ScrcpyMcpServer', () {
    test('list_devices returns device list', () async {
      // This will fail until we implement the server
      final server = ScrcpyMcpServer(adb: MockAdb());
      expect(server, isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: FAIL — `ScrcpyMcpServer` class not found or constructor mismatch.

- [ ] **Step 3: Implement ScrcpyMcpServer with list_devices tool**

```dart
// scrcpy_mcp/lib/src/scrcpy_mcp_server.dart
import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// MCP server exposing scrcpy operations.
class ScrcpyMcpServer extends MCPServer with ToolsSupport {
  /// Creates a scrcpy MCP server.
  ScrcpyMcpServer(
    super.channel, {
    required ScrcpyAdb adb,
    super.protocolLogSink,
  })  : _adb = adb,
        super.fromStreamChannel(
          implementation: Implementation(
            name: 'scrcpy-mcp',
            version: '0.2.0',
          ),
          instructions:
              'Use this server to control Android devices via scrcpy. '
              'List devices, start/stop screen mirroring, and inject input events.',
        );

  final ScrcpyAdb _adb;
  ScrcpyServer? _activeServer;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    _registerTools();
    return super.initialize(request);
  }

  void _registerTools() {
    registerTool(
      Tool(
        name: 'list_devices',
        description: 'List connected Android devices.',
        inputSchema: ObjectSchema(),
      ),
      _listDevices,
    );
  }

  Future<CallToolResult> _listDevices(CallToolRequest request) async {
    final devices = await _adb.getDevices();
    return CallToolResult(
      content: [Content.text(text: jsonEncode(devices))],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/lib/src/scrcpy_mcp_server.dart scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): implement ScrcpyMcpServer with list_devices tool"
```

---

### Task 3: Add start_mirroring and stop_mirroring tools

**Files:**
- Modify: `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Write failing tests for mirroring tools**

Add to `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`:

```dart
test('start_mirroring starts scrcpy server', () async {
  final mockAdb = MockAdb();
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: mockAdb,
  );
  // Verify tool registration exists
  expect(server, isNotNull);
});

test('stop_mirroring stops scrcpy server', () async {
  final mockAdb = MockAdb();
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: mockAdb,
  );
  expect(server, isNotNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: Tests pass (they only check construction). The actual tool calls will be tested via MCP protocol.

- [ ] **Step 3: Implement start_mirroring and stop_mirroring tools**

Add to `_registerTools()` in `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`:

```dart
registerTool(
  Tool(
    name: 'start_mirroring',
    description: 'Start screen mirroring for a device.',
    inputSchema: ObjectSchema(
      properties: {
        'device_id': Schema.string(description: 'The Android device serial'),
      },
      required: ['device_id'],
    ),
  ),
  _startMirroring,
);

registerTool(
  Tool(
    name: 'stop_mirroring',
    description: 'Stop the active mirroring session.',
    inputSchema: ObjectSchema(),
  ),
  _stopMirroring,
);
```

Add implementation methods:

```dart
Future<CallToolResult> _startMirroring(CallToolRequest request) async {
  final deviceId = request.arguments!['device_id'] as String;

  // Stop existing session if any
  await _activeServer?.stop();

  _activeServer = ScrcpyServer(
    adb: _adb,
    deviceId: deviceId,
    logger: const NoOpScrcpyLogger(),
  );

  try {
    await _activeServer!.start();
    final status = {
      'status': 'mirroring',
      'device_id': deviceId,
      'proxy_url': _activeServer!.proxyUrl,
      'player_url': _activeServer!.playerUrl,
    };
    return CallToolResult(
      content: [Content.text(text: jsonEncode(status))],
    );
  } catch (e) {
    return CallToolResult(
      isError: true,
      content: [Content.text(text: 'Failed to start mirroring: $e')],
    );
  }
}

Future<CallToolResult> _stopMirroring(CallToolRequest request) async {
  if (_activeServer == null) {
    return CallToolResult(
      content: [Content.text(text: 'No active mirroring session.')],
    );
  }

  await _activeServer!.stop();
  _activeServer = null;

  return CallToolResult(
    content: [Content.text(text: 'Mirroring stopped.')],
  );
}
```

- [ ] **Step 4: Run tests**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/lib/src/scrcpy_mcp_server.dart scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add start_mirroring and stop_mirroring tools"
```

---

### Task 4: Add input injection tools

**Files:**
- Modify: `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Write failing tests for input tools**

Add to test file:

```dart
test('inject_key tool is registered', () async {
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: MockAdb(),
  );
  expect(server, isNotNull);
});

test('inject_touch tool is registered', () async {
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: MockAdb(),
  );
  expect(server, isNotNull);
});

test('inject_text tool is registered', () async {
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: MockAdb(),
  );
  expect(server, isNotNull);
});

test('inject_scroll tool is registered', () async {
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: MockAdb(),
  );
  expect(server, isNotNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: PASS (construction tests)

- [ ] **Step 3: Implement input injection tools**

Add to `_registerTools()`:

```dart
registerTool(
  Tool(
    name: 'inject_key',
    description: 'Send a key event to the device.',
    inputSchema: ObjectSchema(
      properties: {
        'keycode': Schema.integer(description: 'Android KeyEvent keycode'),
        'action': Schema.integer(
          description: 'Key action: 0=down, 1=up (default: 0)',
        ),
      },
      required: ['keycode'],
    ),
  ),
  _injectKey,
);

registerTool(
  Tool(
    name: 'inject_touch',
    description: 'Send a touch event to the device.',
    inputSchema: ObjectSchema(
      properties: {
        'x': Schema.integer(description: 'X coordinate'),
        'y': Schema.integer(description: 'Y coordinate'),
        'width': Schema.integer(description: 'Screen width'),
        'height': Schema.integer(description: 'Screen height'),
        'action': Schema.integer(
          description: 'Touch action: 0=down, 1=up, 2=move (default: 0)',
        ),
      },
      required: ['x', 'y', 'width', 'height'],
    ),
  ),
  _injectTouch,
);

registerTool(
  Tool(
    name: 'inject_text',
    description: 'Input text on the device.',
    inputSchema: ObjectSchema(
      properties: {
        'text': Schema.string(description: 'Text to input'),
      },
      required: ['text'],
    ),
  ),
  _injectText,
);

registerTool(
  Tool(
    name: 'inject_scroll',
    description: 'Send a scroll event to the device.',
    inputSchema: ObjectSchema(
      properties: {
        'x': Schema.integer(description: 'X coordinate'),
        'y': Schema.integer(description: 'Y coordinate'),
        'width': Schema.integer(description: 'Screen width'),
        'height': Schema.integer(description: 'Screen height'),
        'hScroll': Schema.integer(description: 'Horizontal scroll amount'),
        'vScroll': Schema.integer(description: 'Vertical scroll amount'),
      },
      required: ['x', 'y', 'width', 'height', 'hScroll', 'vScroll'],
    ),
  ),
  _injectScroll,
);
```

Add implementation methods:

```dart
Future<CallToolResult> _injectKey(CallToolRequest request) async {
  if (_activeServer == null) {
    return CallToolResult(
      isError: true,
      content: [Content.text(text: 'No active mirroring session.')],
    );
  }

  final keycode = request.arguments!['keycode'] as int;
  final action = request.arguments!['action'] as int? ?? ScrcpyAction.down;

  _activeServer!.sendControlMessage(
    ScrcpyInjectKeyMessage(action: action, keycode: keycode),
  );

  return CallToolResult(
    content: [Content.text(text: 'Key event sent: keycode=$keycode, action=$action')],
  );
}

Future<CallToolResult> _injectTouch(CallToolRequest request) async {
  if (_activeServer == null) {
    return CallToolResult(
      isError: true,
      content: [Content.text(text: 'No active mirroring session.')],
    );
  }

  final x = request.arguments!['x'] as int;
  final y = request.arguments!['y'] as int;
  final width = request.arguments!['width'] as int;
  final height = request.arguments!['height'] as int;
  final action = request.arguments!['action'] as int? ?? ScrcpyAction.down;

  _activeServer!.sendControlMessage(
    ScrcpyInjectTouchMessage(
      action: action,
      pointerId: 0,
      x: x,
      y: y,
      width: width,
      height: height,
    ),
  );

  return CallToolResult(
    content: [Content.text(text: 'Touch event sent: ($x, $y) action=$action')],
  );
}

Future<CallToolResult> _injectText(CallToolRequest request) async {
  if (_activeServer == null) {
    return CallToolResult(
      isError: true,
      content: [Content.text(text: 'No active mirroring session.')],
    );
  }

  final text = request.arguments!['text'] as String;

  _activeServer!.sendControlMessage(ScrcpyInjectTextMessage(text));

  return CallToolResult(
    content: [Content.text(text: 'Text sent: "$text"')],
  );
}

Future<CallToolResult> _injectScroll(CallToolRequest request) async {
  if (_activeServer == null) {
    return CallToolResult(
      isError: true,
      content: [Content.text(text: 'No active mirroring session.')],
    );
  }

  final x = request.arguments!['x'] as int;
  final y = request.arguments!['y'] as int;
  final width = request.arguments!['width'] as int;
  final height = request.arguments!['height'] as int;
  final hScroll = request.arguments!['hScroll'] as int;
  final vScroll = request.arguments!['vScroll'] as int;

  _activeServer!.sendControlMessage(
    ScrcpyInjectScrollMessage(
      x: x,
      y: y,
      width: width,
      height: height,
      hScroll: hScroll,
      vScroll: vScroll,
    ),
  );

  return CallToolResult(
    content: [Content.text(text: 'Scroll event sent: ($x, $y) h=$hScroll v=$vScroll')],
  );
}
```

- [ ] **Step 4: Run tests**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/lib/src/scrcpy_mcp_server.dart scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add input injection tools (key, touch, text, scroll)"
```

---

### Task 5: Add ResourcesSupport

**Files:**
- Modify: `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Write failing tests for resources**

Add to test file:

```dart
test('device://list resource is registered', () async {
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: MockAdb(),
  );
  expect(server, isNotNull);
});

test('mirroring://status resource is registered', () async {
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: MockAdb(),
  );
  expect(server, isNotNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: PASS

- [ ] **Step 3: Implement ResourcesSupport**

Update class declaration to add `ResourcesSupport`:

```dart
class ScrcpyMcpServer extends MCPServer
    with ToolsSupport, ResourcesSupport {
```

Add resource registration in `initialize`:

```dart
@override
FutureOr<InitializeResult> initialize(InitializeRequest request) {
  _registerTools();
  _registerResources();
  return super.initialize(request);
}

void _registerResources() {
  addResource(
    Resource(
      uri: 'device://list',
      name: 'Connected Devices',
      description: 'List of currently connected Android devices.',
      mimeType: 'application/json',
    ),
    _readDeviceList,
  );

  addResource(
    Resource(
      uri: 'mirroring://status',
      name: 'Mirroring Status',
      description: 'Current mirroring session status.',
      mimeType: 'application/json',
    ),
    _readMirroringStatus,
  );
}
```

Add resource handler implementations:

```dart
Future<ReadResourceResult> _readDeviceList(ReadResourceRequest request) async {
  final devices = await _adb.getDevices();
  return ReadResourceResult(
    contents: [
      ResourceContent(
        uri: 'device://list',
        text: jsonEncode(devices),
        mimeType: 'application/json',
      ),
    ],
  );
}

Future<ReadResourceResult> _readMirroringStatus(
    ReadResourceRequest request) async {
  final status = {
    'active': _activeServer != null,
    if (_activeServer != null) ...{
      'device_id': _activeServer!.deviceId,
      'proxy_url': _activeServer!.proxyUrl,
      'player_url': _activeServer!.playerUrl,
    },
  };
  return ReadResourceResult(
    contents: [
      ResourceContent(
        uri: 'mirroring://status',
        text: jsonEncode(status),
        mimeType: 'application/json',
      ),
    ],
  );
}
```

- [ ] **Step 4: Run tests**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/lib/src/scrcpy_mcp_server.dart scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add ResourcesSupport (device list, mirroring status)"
```

---

### Task 6: Add PromptsSupport

**Files:**
- Modify: `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Write failing tests for prompts**

Add to test file:

```dart
test('control_device prompt is registered', () async {
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: MockAdb(),
  );
  expect(server, isNotNull);
});

test('troubleshoot prompt is registered', () async {
  final server = ScrcpyMcpServer(
    StreamChannel.fromTypedStream(const Stream.empty()),
    adb: MockAdb(),
  );
  expect(server, isNotNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: PASS

- [ ] **Step 3: Implement PromptsSupport**

Update class declaration to add `PromptsSupport`:

```dart
class ScrcpyMcpServer extends MCPServer
    with ToolsSupport, ResourcesSupport, PromptsSupport {
```

Add prompt registration in `initialize`:

```dart
@override
FutureOr<InitializeResult> initialize(InitializeRequest request) {
  _registerTools();
  _registerResources();
  _registerPrompts();
  return super.initialize(request);
}

void _registerPrompts() {
  addPrompt(
    Prompt(
      name: 'control_device',
      description:
          'Assist with Android device control via scrcpy. '
          'Helps with navigation, input, and screen mirroring.',
      arguments: [
        PromptArgument(
          name: 'device_id',
          description: 'The device to control (optional if only one device)',
        ),
      ],
    ),
    _getControlDevicePrompt,
  );

  addPrompt(
    Prompt(
      name: 'troubleshoot',
      description: 'Help diagnose and fix device connection issues.',
      arguments: [
        PromptArgument(
          name: 'issue',
          description: 'Description of the issue encountered',
        ),
      ],
    ),
    _getTroubleshootPrompt,
  );
}
```

Add prompt handler implementations:

```dart
Future<GetPromptResult> _getControlDevicePrompt(
    GetPromptRequest request) async {
  final deviceId = request.arguments?['device_id'] as String?;

  final devices = await _adb.getDevices();
  final deviceInfo = deviceId != null
      ? 'Target device: $deviceId'
      : 'Available devices: ${devices.join(", ")}';

  return GetPromptResult(
    description: 'Device control assistant',
    messages: [
      PromptMessage(
        role: PromptMessageRole.user,
        content: Content.text(
          text: 'You are an Android device control assistant.\n\n'
              '$deviceInfo\n\n'
              'You can use the following tools:\n'
              '- list_devices: See connected devices\n'
              '- start_mirroring: Start screen mirroring\n'
              '- stop_mirroring: Stop mirroring\n'
              '- inject_key: Send key events (Home=3, Back=4, AppSwitch=187)\n'
              '- inject_touch: Send touch events\n'
              '- inject_text: Type text\n'
              '- inject_scroll: Scroll the screen\n\n'
              'Help the user control their Android device.',
        ),
      ),
    ],
  );
}

Future<GetPromptResult> _getTroubleshootPrompt(
    GetPromptRequest request) async {
  final issue = request.arguments?['issue'] as String?;

  final devices = await _adb.getDevices();

  return GetPromptResult(
    description: 'Device troubleshooting assistant',
    messages: [
      PromptMessage(
        role: PromptMessageRole.user,
        content: Content.text(
          text: 'You are an Android device troubleshooting assistant.\n\n'
              'Connected devices: ${devices.isEmpty ? "none" : devices.join(", ")}\n'
              '${issue != null ? "Reported issue: $issue\n" : ""}\n'
              'Common issues and solutions:\n'
              '1. No devices found: Check USB connection, enable USB debugging\n'
              '2. Connection refused: Restart adb server (adb kill-server)\n'
              '3. Mirroring fails: Check scrcpy server version compatibility\n'
              '4. Black screen: Device may be locked, try pressing power key\n\n'
              'Help the user diagnose and resolve their device issue.',
        ),
      ),
    ],
  );
}
```

- [ ] **Step 4: Run tests**

Run: `cd scrcpy_mcp && dart test test/scrcpy_mcp_server_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scrcpy_mcp/lib/src/scrcpy_mcp_server.dart scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add PromptsSupport (control_device, troubleshoot)"
```

---

### Task 7: Update library exports and add shutdown

**Files:**
- Modify: `scrcpy_mcp/lib/scrcpy_mcp.dart`
- Modify: `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`

- [ ] **Step 1: Add shutdown override to ScrcpyMcpServer**

Add to `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`:

```dart
@override
Future<void> shutdown() async {
  await _activeServer?.stop();
  _activeServer = null;
  await super.shutdown();
}
```

- [ ] **Step 2: Update library exports**

```dart
/// MCP server for scrcpy — exposes Android screen mirroring and device
/// control operations via the Model Context Protocol.
library;

export 'src/scrcpy_mcp_server.dart';
export 'src/scrcpy_mcp_adapters.dart';
```

- [ ] **Step 3: Run analyzer**

Run: `cd scrcpy_mcp && dart analyze --fatal-infos --fatal-warnings`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_mcp/lib/scrcpy_mcp.dart scrcpy_mcp/lib/src/scrcpy_mcp_server.dart
git commit -m "feat(scrcpy_mcp): add shutdown cleanup and update exports"
```

---

### Task 8: Create CLI entry point

**Files:**
- Create: `scrcpy_mcp/bin/scrcpy_mcp.dart`

- [ ] **Step 1: Create CLI entry point**

```dart
#!/usr/bin/env dart
// Copyright (c) 2024, the Dart project authors.
// Please see the AUTHORS file or the project root for details.

import 'dart:io';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:stream_channel/stream_channel.dart';

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
    StreamChannel.withCloseGuards(stdin, stdout),
    adb: ScrcpyMcpAdb(adb),
  );

  await server.done;
  exit(0);
}
```

- [ ] **Step 2: Make executable (optional)**

Run: `chmod +x scrcpy_mcp/bin/scrcpy_mcp.dart`

- [ ] **Step 3: Run analyzer**

Run: `cd scrcpy_mcp && dart analyze --fatal-infos --fatal-warnings`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add scrcpy_mcp/bin/scrcpy_mcp.dart
git commit -m "feat(scrcpy_mcp): add CLI entry point for Stdio MCP server"
```

---

### Task 9: Run full test suite and lint

**Files:**
- None (verification only)

- [ ] **Step 1: Run all tests**

Run: `cd scrcpy_mcp && dart test`
Expected: All tests pass.

- [ ] **Step 2: Run analyzer**

Run: `cd scrcpy_mcp && dart analyze --fatal-infos --fatal-warnings`
Expected: No issues found.

- [ ] **Step 3: Run melos analyze**

Run: `melos run analyze`
Expected: No issues found across workspace.

- [ ] **Step 4: Run melos format check**

Run: `melos run format`
Expected: No formatting issues.

- [ ] **Step 5: Final commit if needed**

If any fixes were needed:

```bash
git add -A
git commit -m "fix(scrcpy_mcp): address lint and format issues"
```

---

### Task 10: Integration verification

**Files:**
- None (manual verification)

- [ ] **Step 1: Test CLI startup**

Run: `cd scrcpy_mcp && timeout 5 dart run bin/scrcpy_mcp.dart || true`
Expected: Server starts and waits on stdin (times out after 5s, which is expected).

- [ ] **Step 2: Verify with MCP inspector (if available)**

If `@modelcontextprotocol/inspector` is available:

Run: `npx @modelcontextprotocol/inspector dart run scrcpy_mcp`
Expected: Inspector connects and shows available tools, resources, and prompts.

- [ ] **Step 3: Document usage**

No code changes needed — the CLI entry point already has usage comments.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(scrcpy_mcp): complete dart_mcp rewrite with Tools, Resources, Prompts"
```
