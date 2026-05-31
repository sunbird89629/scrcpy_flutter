import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';
import '../session_context.dart';

/// Captures a PNG screenshot from an Android device via ADB screencap.
///
/// Device resolution is determined by the device; no `width`/`height`
/// arguments are needed. When no `device_id` is supplied the tool falls
/// back to `SessionContext.connectedDeviceId`, then to the first available
/// ADB device.
class TakeScreenshotTool extends McpTool {
  TakeScreenshotTool(this._adb, this._ctx);
  final ScrcpyAdb _adb;
  final SessionContext _ctx;

  @override
  String get name => 'take_screenshot';

  @override
  String get description =>
      'Capture the current screen of the device as a PNG image.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'device_id': JsonSchema.string(
        description:
            'Device serial (optional, uses connected device if omitted)',
      ),
    },
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final deviceIdArg = args['device_id'] as String?;
    final deviceId = deviceIdArg ?? _ctx.connectedDeviceId;
    if (deviceId != null) {
      return _doScreenshot(deviceId);
    }
    final devices = await _adb.getDevices();
    if (devices.isEmpty) {
      return const CallToolResult(
        content: [TextContent(text: 'No devices connected.')],
        isError: true,
      );
    }
    return _doScreenshot(devices.first);
  }

  Future<CallToolResult> _doScreenshot(String deviceId) async {
    logger.fine('take_screenshot: capturing device=$deviceId');
    try {
      final pngBytes = await _adb.takeScreenshot(deviceId);
      logger.fine('take_screenshot: captured ${pngBytes.length} bytes PNG');
      return CallToolResult.fromContent([
        ImageContent(data: base64Encode(pngBytes), mimeType: 'image/png'),
      ]);
    } on Exception catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Screenshot failed: $e')],
        isError: true,
      );
    }
  }
}
