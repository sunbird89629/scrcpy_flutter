import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';
import '../session_context.dart';

List<McpTool> deviceTools(ScrcpyAdb adb, SessionContext ctx) => [
      McpTool(
        name: 'list_devices',
        description: 'List connected Android devices.',
        inputSchema: JsonSchema.object(properties: {}),
        callback: (args, extra) async {
          final devices = await adb.getDevices();
          return CallToolResult.fromContent(
            [TextContent(text: jsonEncode(devices))],
          );
        },
      ),
      McpTool(
        name: 'take_screenshot',
        description: 'Capture the current screen of the device as a PNG image.',
        inputSchema: JsonSchema.object(
          properties: {
            'device_id': JsonSchema.string(
              description:
                  'Device serial (optional, uses connected device if omitted)',
            ),
          },
        ),
        callback: (args, extra) async {
          final deviceIdArg = args['device_id'] as String?;
          final deviceId = deviceIdArg ?? ctx.connectedDeviceId;
          if (deviceId != null) {
            return _doScreenshot(adb, deviceId);
          }
          final devices = await adb.getDevices();
          if (devices.isEmpty) {
            return const CallToolResult(
              content: [TextContent(text: 'No devices connected.')],
              isError: true,
            );
          }
          return _doScreenshot(adb, devices.first);
        },
      ),
    ];

Future<CallToolResult> _doScreenshot(ScrcpyAdb adb, String deviceId) async {
  try {
    final pngBytes = await adb.takeScreenshot(deviceId);
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
