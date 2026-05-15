# scrcpy_mcp New Control Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 9 new MCP tools to `scrcpy_mcp` covering navigation, clipboard, panel, and camera control message types.

**Architecture:** Each tool is a single `.dart` file in `scrcpy_mcp/lib/src/tools/` that extends `McpTool`, calls `_session.sendControlMessage(...)` with the appropriate `ScrcpyControlMessage` from `scrcpy_client`, and returns a text result. Tools are registered in `ScrcpyMcpServer`. Tests live in `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`.

**Tech Stack:** Dart, `package:mcp_dart`, `package:scrcpy_client`, `package:test`

---

## File Map

| File | Action |
|------|--------|
| `scrcpy_mcp/lib/src/tools/press_back.dart` | Create |
| `scrcpy_mcp/lib/src/tools/set_screen_power.dart` | Create |
| `scrcpy_mcp/lib/src/tools/rotate_device.dart` | Create |
| `scrcpy_mcp/lib/src/tools/set_clipboard.dart` | Create |
| `scrcpy_mcp/lib/src/tools/expand_notification_panel.dart` | Create |
| `scrcpy_mcp/lib/src/tools/expand_settings_panel.dart` | Create |
| `scrcpy_mcp/lib/src/tools/collapse_panels.dart` | Create |
| `scrcpy_mcp/lib/src/tools/set_torch.dart` | Create |
| `scrcpy_mcp/lib/src/tools/camera_zoom.dart` | Create |
| `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart` | Modify — add 9 imports + 9 registrations, update tool count |
| `scrcpy_mcp/test/scrcpy_mcp_server_test.dart` | Modify — update tool count test + add 9 tool test groups |

---

### Task 1: Navigation tools — `press_back`, `set_screen_power`, `rotate_device`

**Files:**
- Create: `scrcpy_mcp/lib/src/tools/press_back.dart`
- Create: `scrcpy_mcp/lib/src/tools/set_screen_power.dart`
- Create: `scrcpy_mcp/lib/src/tools/rotate_device.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Add failing tests for the three navigation tools**

In `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`, inside `group('ScrcpyMcpServer — tools', ...)`, add after the existing tool tests:

```dart
    test('press_back without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'press_back'),
      );
      expect(result.isError, isTrue);
    });

    test('press_back sends down then up BackOrScreenOn messages', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'press_back'),
      );
      expect(result.isError, isFalse);
      expect(env.session.sentMessages, hasLength(2));
      expect(env.session.sentMessages[0], isA<ScrcpyBackOrScreenOnMessage>());
      expect((env.session.sentMessages[0] as ScrcpyBackOrScreenOnMessage).action, ScrcpyAction.down);
      expect(env.session.sentMessages[1], isA<ScrcpyBackOrScreenOnMessage>());
      expect((env.session.sentMessages[1] as ScrcpyBackOrScreenOnMessage).action, ScrcpyAction.up);
    });

    test('set_screen_power without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'set_screen_power', arguments: {'on': true}),
      );
      expect(result.isError, isTrue);
    });

    test('set_screen_power sends SetDisplayPowerMessage', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'set_screen_power', arguments: {'on': false}),
      );
      expect(result.isError, isFalse);
      expect(env.session.sentMessages, hasLength(1));
      final msg = env.session.sentMessages.single as ScrcpySetDisplayPowerMessage;
      expect(msg.on, isFalse);
    });

    test('rotate_device without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'rotate_device'),
      );
      expect(result.isError, isTrue);
    });

    test('rotate_device sends RotateDeviceMessage', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'rotate_device'),
      );
      expect(result.isError, isFalse);
      expect(env.session.sentMessages.single, isA<ScrcpyRotateDeviceMessage>());
    });
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp
dart test test/scrcpy_mcp_server_test.dart 2>&1 | tail -20
```

Expected: errors about `press_back`, `set_screen_power`, `rotate_device` tools not found.

- [ ] **Step 3: Create `press_back.dart`**

```dart
// scrcpy_mcp/lib/src/tools/press_back.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class PressBackTool extends McpTool {
  PressBackTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'press_back';

  @override
  String get description =>
      'Send a Back button press to the device (down then up). '
      'Also wakes the screen if it is off.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(
      const ScrcpyBackOrScreenOnMessage(ScrcpyAction.down),
    );
    _session.sendControlMessage(
      const ScrcpyBackOrScreenOnMessage(ScrcpyAction.up),
    );
    return CallToolResult.fromContent([
      TextContent(text: 'Back button pressed.'),
    ]);
  }
}
```

- [ ] **Step 4: Create `set_screen_power.dart`**

```dart
// scrcpy_mcp/lib/src/tools/set_screen_power.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class SetScreenPowerTool extends McpTool {
  SetScreenPowerTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'set_screen_power';

  @override
  String get description => 'Turn the device screen on or off.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'on': JsonSchema.boolean(description: 'true to turn on, false to turn off'),
    },
    required: ['on'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final on = args['on'] as bool;
    _session.sendControlMessage(ScrcpySetDisplayPowerMessage(on: on));
    return CallToolResult.fromContent([
      TextContent(text: on ? 'Screen turned on.' : 'Screen turned off.'),
    ]);
  }
}
```

- [ ] **Step 5: Create `rotate_device.dart`**

```dart
// scrcpy_mcp/lib/src/tools/rotate_device.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class RotateDeviceTool extends McpTool {
  RotateDeviceTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'rotate_device';

  @override
  String get description => 'Rotate the device display 90 degrees.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(const ScrcpyRotateDeviceMessage());
    return CallToolResult.fromContent([TextContent(text: 'Rotate sent.')]);
  }
}
```

- [ ] **Step 6: Register the 3 tools in `ScrcpyMcpServer`**

In `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`, add 3 imports near the other tool imports:

```dart
import 'tools/press_back.dart';
import 'tools/rotate_device.dart';
import 'tools/set_screen_power.dart';
```

Then add the 3 tools to the tool list (after `StartAppTool`):

```dart
      PressBackTool(_session),
      SetScreenPowerTool(_session),
      RotateDeviceTool(_session),
```

- [ ] **Step 7: Run tests — all should pass**

```bash
dart test test/scrcpy_mcp_server_test.dart 2>&1 | tail -10
```

Expected: all navigation tool tests pass; `advertises 9 tools` test still passes (count not updated yet).

- [ ] **Step 8: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_mcp/lib/src/tools/press_back.dart \
        scrcpy_mcp/lib/src/tools/set_screen_power.dart \
        scrcpy_mcp/lib/src/tools/rotate_device.dart \
        scrcpy_mcp/lib/src/scrcpy_mcp_server.dart \
        scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add press_back, set_screen_power, rotate_device tools"
```

---

### Task 2: Clipboard tool — `set_clipboard`

**Files:**
- Create: `scrcpy_mcp/lib/src/tools/set_clipboard.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Add failing tests**

In `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`, inside `group('ScrcpyMcpServer — tools', ...)`, add:

```dart
    test('set_clipboard without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'set_clipboard', arguments: {'text': 'hello'}),
      );
      expect(result.isError, isTrue);
    });

    test('set_clipboard sends SetClipboardMessage with paste=false by default', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'set_clipboard', arguments: {'text': 'hello'}),
      );
      expect(result.isError, isFalse);
      final msg = env.session.sentMessages.single as ScrcpySetClipboardMessage;
      expect(msg.text, 'hello');
      expect(msg.paste, isFalse);
    });

    test('set_clipboard with paste=true sends SetClipboardMessage with paste=true', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'set_clipboard',
          arguments: {'text': 'hello', 'paste': true},
        ),
      );
      expect(result.isError, isFalse);
      final msg = env.session.sentMessages.single as ScrcpySetClipboardMessage;
      expect(msg.text, 'hello');
      expect(msg.paste, isTrue);
    });
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp
dart test test/scrcpy_mcp_server_test.dart 2>&1 | tail -10
```

Expected: errors about `set_clipboard` tool not found.

- [ ] **Step 3: Create `set_clipboard.dart`**

```dart
// scrcpy_mcp/lib/src/tools/set_clipboard.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class SetClipboardTool extends McpTool {
  SetClipboardTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'set_clipboard';

  @override
  String get description =>
      'Write text to the device clipboard. '
      'Pass paste=true to also paste immediately into the focused field.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'text': JsonSchema.string(description: 'Text to place on the clipboard'),
      'paste': JsonSchema.boolean(
        description: 'Whether to paste the text immediately (default: false)',
      ),
    },
    required: ['text'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final text = args['text'] as String;
    final paste = args['paste'] as bool? ?? false;
    _session.sendControlMessage(ScrcpySetClipboardMessage(text: text, paste: paste));
    return CallToolResult.fromContent([
      TextContent(text: paste ? 'Clipboard set and pasted.' : 'Clipboard set.'),
    ]);
  }
}
```

- [ ] **Step 4: Register in `ScrcpyMcpServer`**

Add import:

```dart
import 'tools/set_clipboard.dart';
```

Add to tool list:

```dart
      SetClipboardTool(_session),
```

- [ ] **Step 5: Run tests — all should pass**

```bash
dart test test/scrcpy_mcp_server_test.dart 2>&1 | tail -10
```

Expected: all set_clipboard tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_mcp/lib/src/tools/set_clipboard.dart \
        scrcpy_mcp/lib/src/scrcpy_mcp_server.dart \
        scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add set_clipboard tool"
```

---

### Task 3: Panel tools — `expand_notification_panel`, `expand_settings_panel`, `collapse_panels`

**Files:**
- Create: `scrcpy_mcp/lib/src/tools/expand_notification_panel.dart`
- Create: `scrcpy_mcp/lib/src/tools/expand_settings_panel.dart`
- Create: `scrcpy_mcp/lib/src/tools/collapse_panels.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Add failing tests**

In `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`, inside `group('ScrcpyMcpServer — tools', ...)`, add:

```dart
    test('expand_notification_panel without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'expand_notification_panel'),
      );
      expect(result.isError, isTrue);
    });

    test('expand_notification_panel sends ExpandNotificationPanelMessage', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'expand_notification_panel'),
      );
      expect(result.isError, isFalse);
      expect(env.session.sentMessages.single, isA<ScrcpyExpandNotificationPanelMessage>());
    });

    test('expand_settings_panel without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'expand_settings_panel'),
      );
      expect(result.isError, isTrue);
    });

    test('expand_settings_panel sends ExpandSettingsPanelMessage', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'expand_settings_panel'),
      );
      expect(result.isError, isFalse);
      expect(env.session.sentMessages.single, isA<ScrcpyExpandSettingsPanelMessage>());
    });

    test('collapse_panels without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'collapse_panels'),
      );
      expect(result.isError, isTrue);
    });

    test('collapse_panels sends CollapsePanelsMessage', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'collapse_panels'),
      );
      expect(result.isError, isFalse);
      expect(env.session.sentMessages.single, isA<ScrcpyCollapsePanelsMessage>());
    });
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp
dart test test/scrcpy_mcp_server_test.dart 2>&1 | tail -10
```

Expected: errors about the three panel tool names not found.

- [ ] **Step 3: Create `expand_notification_panel.dart`**

```dart
// scrcpy_mcp/lib/src/tools/expand_notification_panel.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class ExpandNotificationPanelTool extends McpTool {
  ExpandNotificationPanelTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'expand_notification_panel';

  @override
  String get description =>
      'Expand the notification panel (equivalent to swiping down from the top).';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(const ScrcpyExpandNotificationPanelMessage());
    return CallToolResult.fromContent([
      TextContent(text: 'Notification panel expanded.'),
    ]);
  }
}
```

- [ ] **Step 4: Create `expand_settings_panel.dart`**

```dart
// scrcpy_mcp/lib/src/tools/expand_settings_panel.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class ExpandSettingsPanelTool extends McpTool {
  ExpandSettingsPanelTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'expand_settings_panel';

  @override
  String get description =>
      'Expand the quick-settings panel (equivalent to a two-finger swipe down).';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(const ScrcpyExpandSettingsPanelMessage());
    return CallToolResult.fromContent([
      TextContent(text: 'Settings panel expanded.'),
    ]);
  }
}
```

- [ ] **Step 5: Create `collapse_panels.dart`**

```dart
// scrcpy_mcp/lib/src/tools/collapse_panels.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class CollapsePanelsTool extends McpTool {
  CollapsePanelsTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'collapse_panels';

  @override
  String get description => 'Collapse any open notification or settings panel.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    _session.sendControlMessage(const ScrcpyCollapsePanelsMessage());
    return CallToolResult.fromContent([TextContent(text: 'Panels collapsed.')]);
  }
}
```

- [ ] **Step 6: Register the 3 tools in `ScrcpyMcpServer`**

Add 3 imports:

```dart
import 'tools/collapse_panels.dart';
import 'tools/expand_notification_panel.dart';
import 'tools/expand_settings_panel.dart';
```

Add to tool list:

```dart
      ExpandNotificationPanelTool(_session),
      ExpandSettingsPanelTool(_session),
      CollapsePanelsTool(_session),
```

- [ ] **Step 7: Run tests — all should pass**

```bash
dart test test/scrcpy_mcp_server_test.dart 2>&1 | tail -10
```

Expected: all panel tool tests pass.

- [ ] **Step 8: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_mcp/lib/src/tools/expand_notification_panel.dart \
        scrcpy_mcp/lib/src/tools/expand_settings_panel.dart \
        scrcpy_mcp/lib/src/tools/collapse_panels.dart \
        scrcpy_mcp/lib/src/scrcpy_mcp_server.dart \
        scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add expand_notification_panel, expand_settings_panel, collapse_panels tools"
```

---

### Task 4: Camera tools — `set_torch`, `camera_zoom`

**Files:**
- Create: `scrcpy_mcp/lib/src/tools/set_torch.dart`
- Create: `scrcpy_mcp/lib/src/tools/camera_zoom.dart`
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Add failing tests**

In `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`, inside `group('ScrcpyMcpServer — tools', ...)`, add:

```dart
    test('set_torch without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'set_torch', arguments: {'on': true}),
      );
      expect(result.isError, isTrue);
    });

    test('set_torch sends CameraSetTorchMessage', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'set_torch', arguments: {'on': true}),
      );
      expect(result.isError, isFalse);
      final msg = env.session.sentMessages.single as ScrcpyCameraSetTorchMessage;
      expect(msg.on, isTrue);
    });

    test('camera_zoom without active session returns error', () async {
      final env = _TestEnv();
      await env.connect();
      final result = await env.client.callTool(
        const CallToolRequest(name: 'camera_zoom', arguments: {'direction': 'in'}),
      );
      expect(result.isError, isTrue);
    });

    test('camera_zoom in sends CameraZoomInMessage', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'camera_zoom', arguments: {'direction': 'in'}),
      );
      expect(result.isError, isFalse);
      expect(env.session.sentMessages.single, isA<ScrcpyCameraZoomInMessage>());
    });

    test('camera_zoom out sends CameraZoomOutMessage', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'camera_zoom', arguments: {'direction': 'out'}),
      );
      expect(result.isError, isFalse);
      expect(env.session.sentMessages.single, isA<ScrcpyCameraZoomOutMessage>());
    });

    test('camera_zoom invalid direction returns error', () async {
      final env = _TestEnv();
      await env.connect();
      await env.client.callTool(
        const CallToolRequest(name: 'start_mirroring', arguments: {'device_id': 'device1'}),
      );
      final result = await env.client.callTool(
        const CallToolRequest(name: 'camera_zoom', arguments: {'direction': 'sideways'}),
      );
      expect(result.isError, isTrue);
    });
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp
dart test test/scrcpy_mcp_server_test.dart 2>&1 | tail -10
```

Expected: errors about `set_torch` and `camera_zoom` tools not found.

- [ ] **Step 3: Create `set_torch.dart`**

```dart
// scrcpy_mcp/lib/src/tools/set_torch.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class SetTorchTool extends McpTool {
  SetTorchTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'set_torch';

  @override
  String get description => 'Turn the device flashlight/torch on or off.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'on': JsonSchema.boolean(description: 'true to turn on, false to turn off'),
    },
    required: ['on'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final on = args['on'] as bool;
    _session.sendControlMessage(ScrcpyCameraSetTorchMessage(on: on));
    return CallToolResult.fromContent([
      TextContent(text: on ? 'Torch turned on.' : 'Torch turned off.'),
    ]);
  }
}
```

- [ ] **Step 4: Create `camera_zoom.dart`**

```dart
// scrcpy_mcp/lib/src/tools/camera_zoom.dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

class CameraZoomTool extends McpTool {
  CameraZoomTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'camera_zoom';

  @override
  String get description => 'Zoom the device camera in or out by one step.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'direction': JsonSchema.string(
        description: 'Zoom direction: "in" or "out"',
      ),
    },
    required: ['direction'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final direction = args['direction'] as String;
    if (direction == 'in') {
      _session.sendControlMessage(const ScrcpyCameraZoomInMessage());
      return CallToolResult.fromContent([TextContent(text: 'Camera zoomed in.')]);
    } else if (direction == 'out') {
      _session.sendControlMessage(const ScrcpyCameraZoomOutMessage());
      return CallToolResult.fromContent([TextContent(text: 'Camera zoomed out.')]);
    }
    return CallToolResult(
      content: [TextContent(text: 'Invalid direction: "$direction". Use "in" or "out".')],
      isError: true,
    );
  }
}
```

- [ ] **Step 5: Register the 2 tools in `ScrcpyMcpServer`**

Add 2 imports:

```dart
import 'tools/camera_zoom.dart';
import 'tools/set_torch.dart';
```

Add to tool list:

```dart
      SetTorchTool(_session),
      CameraZoomTool(_session),
```

- [ ] **Step 6: Run tests — all should pass**

```bash
dart test test/scrcpy_mcp_server_test.dart 2>&1 | tail -10
```

Expected: all camera tool tests pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_mcp/lib/src/tools/set_torch.dart \
        scrcpy_mcp/lib/src/tools/camera_zoom.dart \
        scrcpy_mcp/lib/src/scrcpy_mcp_server.dart \
        scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "feat(scrcpy_mcp): add set_torch and camera_zoom tools"
```

---

### Task 5: Update tool count test + final check

**Files:**
- Modify: `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`

- [ ] **Step 1: Update the `advertises N tools` test**

In `scrcpy_mcp/test/scrcpy_mcp_server_test.dart`, find:

```dart
    test('advertises 9 tools after connect', () async {
```

Change to `18 tools` and add the 9 new tool names to the `containsAll` list:

```dart
    test('advertises 18 tools after connect', () async {
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
          'press_back',
          'set_screen_power',
          'rotate_device',
          'set_clipboard',
          'expand_notification_panel',
          'expand_settings_panel',
          'collapse_panels',
          'set_torch',
          'camera_zoom',
        ]),
      );
    });
```

- [ ] **Step 2: Run the full test suite**

```bash
cd /Users/hao/ai/mobile/asf_dev/scrcpy_mcp
dart test 2>&1 | tail -15
```

Expected: all tests pass, no failures.

- [ ] **Step 3: Run dart analyze**

```bash
cd /Users/hao/ai/mobile/asf_dev
dart analyze scrcpy_mcp/ 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd /Users/hao/ai/mobile/asf_dev
git add scrcpy_mcp/test/scrcpy_mcp_server_test.dart
git commit -m "test(scrcpy_mcp): update tool count to 18 in advertises test"
```
