# scrcpy_mcp — New Control Tool Coverage

**Date:** 2026-05-15
**Package:** `scrcpy_mcp`
**Status:** Approved

---

## Goal

Expose 9 additional scrcpy v3 control message types as MCP tools, expanding the AI-accessible surface from 4 control-message tools to 13. All new tools follow the existing one-file-per-tool pattern and require zero structural changes to `McpTool`, `ScrcpySession`, or `ScrcpyMcpServer`.

---

## Out of Scope

- `GetClipboard` (type 8): response travels device-to-host; `ScrcpyServer` has no device message parser — deferred.
- UHID messages (types 12–14), `OpenHardKeyboardSettings` (type 15), `StartApp` via type 16 (already covered), `ResetVideo` (type 17), `ResizeDisplay` (type 21): not requested.

---

## New Tool Files

All files go in `scrcpy_mcp/lib/src/tools/`.

### Navigation

**`press_back.dart` — `PressBackTool`**
- MCP name: `press_back`
- Description: "Send a Back button press to the device (down then up). Also wakes the screen if it is off."
- Input schema: no parameters
- Implementation: sends `ScrcpyBackOrScreenOnMessage(ScrcpyAction.down)` then `ScrcpyBackOrScreenOnMessage(ScrcpyAction.up)`
- Returns: `'Back button pressed.'`

**`set_screen_power.dart` — `SetScreenPowerTool`**
- MCP name: `set_screen_power`
- Description: "Turn the device screen on or off."
- Input schema: `on: bool` (required)
- Implementation: `ScrcpySetDisplayPowerMessage(on: on)`
- Returns: `'Screen turned on.'` / `'Screen turned off.'`

**`rotate_device.dart` — `RotateDeviceTool`**
- MCP name: `rotate_device`
- Description: "Rotate the device display 90 degrees."
- Input schema: no parameters
- Implementation: `ScrcpyRotateDeviceMessage()`
- Returns: `'Rotate sent.'`

### Clipboard

**`set_clipboard.dart` — `SetClipboardTool`**
- MCP name: `set_clipboard`
- Description: "Write text to the device clipboard. Pass paste=true to also paste immediately into the focused field."
- Input schema: `text: string` (required), `paste: bool` (optional, default `false`)
- Implementation: `ScrcpySetClipboardMessage(text: text, paste: paste)`
- Returns: `'Clipboard set.'` / `'Clipboard set and pasted.'`

### Panels

**`expand_notification_panel.dart` — `ExpandNotificationPanelTool`**
- MCP name: `expand_notification_panel`
- Description: "Expand the notification panel (equivalent to swiping down from the top)."
- Input schema: no parameters
- Implementation: `ScrcpyExpandNotificationPanelMessage()`
- Returns: `'Notification panel expanded.'`

**`expand_settings_panel.dart` — `ExpandSettingsPanelTool`**
- MCP name: `expand_settings_panel`
- Description: "Expand the quick-settings panel (equivalent to a two-finger swipe down)."
- Input schema: no parameters
- Implementation: `ScrcpyExpandSettingsPanelMessage()`
- Returns: `'Settings panel expanded.'`

**`collapse_panels.dart` — `CollapsePanelsTool`**
- MCP name: `collapse_panels`
- Description: "Collapse any open notification or settings panel."
- Input schema: no parameters
- Implementation: `ScrcpyCollapsePanelsMessage()`
- Returns: `'Panels collapsed.'`

### Camera

**`set_torch.dart` — `SetTorchTool`**
- MCP name: `set_torch`
- Description: "Turn the device flashlight/torch on or off."
- Input schema: `on: bool` (required)
- Implementation: `ScrcpyCameraSetTorchMessage(on: on)`
- Returns: `'Torch turned on.'` / `'Torch turned off.'`

**`camera_zoom.dart` — `CameraZoomTool`**
- MCP name: `camera_zoom`
- Description: "Zoom the device camera in or out by one step."
- Input schema: `direction: string` (required, `'in'` or `'out'`)
- Implementation: `direction == 'in'` → `ScrcpyCameraZoomInMessage()`, otherwise → `ScrcpyCameraZoomOutMessage()`
- Returns: `'Camera zoomed in.'` / `'Camera zoomed out.'`
- Error: returns `isError: true` if direction is not `'in'` or `'out'`

---

## Registration

In `scrcpy_mcp/lib/src/scrcpy_mcp_server.dart`, append the 9 new tools to the existing tool list (around line 63):

```dart
PressBackTool(_session),
SetScreenPowerTool(_session),
RotateDeviceTool(_session),
SetClipboardTool(_session),
ExpandNotificationPanelTool(_session),
ExpandSettingsPanelTool(_session),
CollapsePanelsTool(_session),
SetTorchTool(_session),
CameraZoomTool(_session),
```

All constructors take `ScrcpySession` only — no new dependencies.

---

## Imports

Each new tool file imports:
```dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';
import '../mcp_tool.dart';
```

`scrcpy_mcp_server.dart` adds 9 corresponding import lines for the new tool files and 9 registration lines in the tool list.

---

## Testing

No new test files required. The tool logic is a thin wrapper over `sendControlMessage` — the message encoding is already tested in `scrcpy_client`. Manual verification with a connected device covers the happy path.

---

## File Change Summary

| File | Change |
|------|--------|
| `lib/src/tools/press_back.dart` | New |
| `lib/src/tools/set_screen_power.dart` | New |
| `lib/src/tools/rotate_device.dart` | New |
| `lib/src/tools/set_clipboard.dart` | New |
| `lib/src/tools/expand_notification_panel.dart` | New |
| `lib/src/tools/expand_settings_panel.dart` | New |
| `lib/src/tools/collapse_panels.dart` | New |
| `lib/src/tools/set_torch.dart` | New |
| `lib/src/tools/camera_zoom.dart` | New |
| `lib/src/scrcpy_mcp_server.dart` | Add 9 imports + 9 tool registrations |
