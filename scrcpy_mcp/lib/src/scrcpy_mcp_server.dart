import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import 'recording_adb.dart';
import 'recording_controller.dart';
import 'session_context.dart';
import 'tools/device_tools.dart';
import 'tools/input_tools.dart';
import 'tools/mirroring_tools.dart';
import 'tools/recording_tools.dart';

/// MCP server exposing scrcpy operations via the Model Context Protocol.
class ScrcpyMcpServer {
  ScrcpyMcpServer({
    required ScrcpySession session,
    required ScrcpyAdb adb,
    RecordingAdb? recordingAdb,
  })  : _session = session,
        _adb = adb,
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
      ...deviceTools(_adb, _ctx),
      ...mirroringTools(_session, _ctx),
      ...inputTools(_session),
      if (_recordingController != null)
        ...recordingTools(
          _recordingController!,
          _ctx,
          _session,
        ),
    ];
    for (final tool in tools) {
      _mcpServer.registerTool(
        tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema,
        callback: tool.callback,
      );
    }
  }

  void _registerResources() {
    _mcpServer
      ..registerResource(
        'Connected Devices',
        'device://list',
        (
          description: 'List of currently connected Android devices.',
          mimeType: 'application/json',
        ),
        _readDeviceList,
      )
      ..registerResource(
        'Mirroring Status',
        'mirroring://status',
        (
          description: 'Current mirroring session status.',
          mimeType: 'application/json',
        ),
        _readMirroringStatus,
      );

    if (_recordingController != null) {
      _mcpServer.registerResource(
        'Recording Status',
        'recording://status',
        (
          description: 'Current screen recording state.',
          mimeType: 'application/json',
        ),
        _readRecordingStatus,
      );
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
            text: 'You are an Android device control assistant.\n\n'
                '$deviceInfo\n\n'
                'Available tools:\n'
                '- list_devices, start_mirroring, stop_mirroring\n'
                '- inject_key (Home=3, Back=4, AppSwitch=187)\n'
                '- inject_touch, inject_text, inject_scroll\n'
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
            text: 'You are an Android device troubleshooting assistant.\n\n'
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
