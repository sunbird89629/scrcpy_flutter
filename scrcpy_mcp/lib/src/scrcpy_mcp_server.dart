import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import 'agent/agent_config.dart';
import 'agent/llm_client.dart';
import 'recording_adb.dart';
import 'recording_controller.dart';
import 'session_context.dart';
import 'tools/run_task.dart' show RunTaskTool;
import 'tools/camera_zoom.dart' show CameraZoomTool;
import 'tools/collapse_panels.dart' show CollapsePanelsTool;
import 'tools/expand_notification_panel.dart' show ExpandNotificationPanelTool;
import 'tools/expand_settings_panel.dart' show ExpandSettingsPanelTool;
import 'tools/get_clipboard.dart' show GetClipboardTool;
import 'tools/inject_key.dart' show InjectKeyTool;
import 'tools/inject_scroll.dart' show InjectScrollTool;
import 'tools/inject_swipe.dart' show InjectSwipeTool;
import 'tools/inject_text.dart' show InjectTextTool;
import 'tools/inject_touch.dart' show InjectTouchTool;
import 'tools/list_devices.dart' show ListDevicesTool;
import 'tools/press_back.dart' show PressBackTool;
import 'tools/rotate_device.dart' show RotateDeviceTool;
import 'tools/set_clipboard.dart' show SetClipboardTool;
import 'tools/set_screen_power.dart' show SetScreenPowerTool;
import 'tools/set_torch.dart' show SetTorchTool;
import 'tools/start_app.dart' show StartAppTool;
import 'tools/start_mirroring.dart' show StartMirroringTool;
import 'tools/start_recording.dart' show StartRecordingTool;
import 'tools/stop_mirroring.dart' show StopMirroringTool;
import 'tools/stop_recording.dart' show StopRecordingTool;
import 'tools/take_screenshot.dart' show TakeScreenshotTool;

/// MCP server exposing scrcpy operations via the Model Context Protocol.
class ScrcpyMcpServer {
  ScrcpyMcpServer({
    required ScrcpySession session,
    required ScrcpyAdb adb,
    RecordingAdb? recordingAdb,
    AgentConfig? agentConfig,
    LlmClient? llmClient,
  }) : _session = session,
       _adb = adb,
       _agentConfig = agentConfig,
       _llmClient = llmClient,
       _ctx = SessionContext() {
    if (recordingAdb != null) {
      _recordingController = RecordingController(recordingAdb);
    }
    _mcpServer = McpServer(
      const Implementation(name: 'scrcpy-mcp', version: '0.2.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
          resources: ServerCapabilitiesResources(),
          prompts: ServerCapabilitiesPrompts(),
        ),
      ),
    );
    _registerAll();
  }

  final ScrcpySession _session;
  final ScrcpyAdb _adb;
  final SessionContext _ctx;
  final AgentConfig? _agentConfig;
  final LlmClient? _llmClient;
  late final McpServer _mcpServer;
  RecordingController? _recordingController;

  McpServer get mcpServer => _mcpServer;

  void _registerAll() {
    _registerTools();
    _registerResources();
    _registerPrompts();
  }

  void _registerTools() {
    final tools = [
      ListDevicesTool(_adb),
      TakeScreenshotTool(_adb, _ctx),
      StartMirroringTool(_session, _ctx),
      StopMirroringTool(_session, _ctx),
      InjectKeyTool(_session),
      InjectTouchTool(_session),
      InjectTextTool(_session),
      InjectScrollTool(_session),
      InjectSwipeTool(_session),
      StartAppTool(_session),
      PressBackTool(_session),
      SetScreenPowerTool(_session),
      RotateDeviceTool(_session),
      SetClipboardTool(_session),
      GetClipboardTool(_session),
      ExpandNotificationPanelTool(_session),
      ExpandSettingsPanelTool(_session),
      CollapsePanelsTool(_session),
      SetTorchTool(_session),
      CameraZoomTool(_session),
      if (_recordingController != null) ...[
        StartRecordingTool(_recordingController!, _ctx, _session),
        StopRecordingTool(_recordingController!),
      ],
    ];

    // Agent tool — only when both config and client are provided.
    // Built after all other tools so it can reference their schemas.
    if (_agentConfig != null && _llmClient != null) {
      tools.add(
        RunTaskTool(
          config: _agentConfig,
          llmClient: _llmClient,
          tools: List.unmodifiable(tools),
          session: _session,
          ctx: _ctx,
        ),
      );
    }

    for (final tool in tools) {
      _mcpServer.registerTool(
        tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema,
        callback: tool.call,
      );
    }
  }

  void _registerResources() {
    _mcpServer
      ..registerResource('Connected Devices', 'device://list', (
        description: 'List of currently connected Android devices.',
        mimeType: 'application/json',
      ), _readDeviceList)
      ..registerResource('Mirroring Status', 'mirroring://status', (
        description: 'Current mirroring session status.',
        mimeType: 'application/json',
      ), _readMirroringStatus);

    if (_recordingController != null) {
      _mcpServer.registerResource('Recording Status', 'recording://status', (
        description: 'Current screen recording state.',
        mimeType: 'application/json',
      ), _readRecordingStatus);
    }
  }

  void _registerPrompts() {
    _mcpServer
      ..registerPrompt(
        'control_device',
        description: 'Assist with Android device control via scrcpy.',
        argsSchema: {
          'device_id': const PromptArgumentDefinition(
            description: 'The device to control (optional if only one device)',
          ),
        },
        callback: _getControlDevicePrompt,
      )
      ..registerPrompt(
        'troubleshoot',
        description: 'Help diagnose and fix device connection issues.',
        argsSchema: {
          'issue': const PromptArgumentDefinition(
            description: 'Description of the issue encountered',
          ),
        },
        callback: _getTroubleshootPrompt,
      );
  }

  // ── Resource implementations ──────────────────────────────────────────────

  Future<ReadResourceResult> _readDeviceList(
    Uri uri,
    RequestHandlerExtra extra,
  ) async {
    final devices = await _adb.getDevices();
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: jsonEncode(devices),
        ),
      ],
    );
  }

  Future<ReadResourceResult> _readMirroringStatus(
    Uri uri,
    RequestHandlerExtra extra,
  ) async {
    final status = <String, dynamic>{
      'active': _session.isConnected,
      if (_ctx.connectedDeviceId != null) 'device_id': _ctx.connectedDeviceId,
    };
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: jsonEncode(status),
        ),
      ],
    );
  }

  Future<ReadResourceResult> _readRecordingStatus(
    Uri uri,
    RequestHandlerExtra extra,
  ) async {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: jsonEncode(_recordingController!.status.toJson()),
        ),
      ],
    );
  }

  // ── Prompt implementations ────────────────────────────────────────────────

  Future<GetPromptResult> _getControlDevicePrompt(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    final deviceId = args?['device_id'] as String?;
    final devices = await _adb.getDevices();
    final deviceInfo = deviceId != null
        ? 'Target device: $deviceId'
        : 'Available devices: ${devices.join(", ")}';
    final recordingLine = _recordingController != null
        ? '- start_recording, stop_recording '
              '(max 180 s; requires active mirroring)\n'
        : '';

    return GetPromptResult(
      description: 'Device control assistant',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text:
                'You are an Android device control assistant.\n\n'
                '$deviceInfo\n\n'
                'Available tools:\n'
                '- list_devices, start_mirroring, stop_mirroring\n'
                '- inject_key (Home=3, Back=4, AppSwitch=187)\n'
                '- inject_touch, inject_text, inject_scroll, inject_swipe\n'
                '- press_back, set_screen_power, rotate_device\n'
                '- set_clipboard, get_clipboard\n'
                '- expand_notification_panel, expand_settings_panel, collapse_panels\n'
                '- set_torch, camera_zoom\n'
                '- start_app (launch app by package name)\n'
                '- take_screenshot\n'
                '$recordingLine\n'
                'Help the user control their Android device.',
          ),
        ),
      ],
    );
  }

  Future<GetPromptResult> _getTroubleshootPrompt(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    final issue = args?['issue'] as String?;
    final devices = await _adb.getDevices();

    return GetPromptResult(
      description: 'Device troubleshooting assistant',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(
            text:
                'You are an Android device troubleshooting assistant.\n\n'
                'Connected devices: '
                '${devices.isEmpty ? "none" : devices.join(", ")}\n'
                '${issue != null ? "Reported issue: $issue\n" : ""}\n'
                'Common issues:\n'
                '1. No devices: Check USB connection, enable USB debugging\n'
                '2. Connection refused: Run adb kill-server\n'
                '3. Mirroring fails: Check scrcpy server version\n'
                '4. Black screen: Device may be locked\n'
                '5. Black recording: Protected content (payment/login screens) '
                'records as black — Android security restriction.\n\n'
                'Help the user diagnose and resolve their issue.',
          ),
        ),
      ],
    );
  }
}
