import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_view/scrcpy_core.dart';

import '../mcp_tool.dart';

McpTool listDevicesTool(ScrcpyAdb adb) => McpTool(
      name: 'list_devices',
      description: 'List connected Android devices.',
      inputSchema: JsonSchema.object(properties: {}),
      callback: (args, extra) async {
        final devices = await adb.getDevices();
        return CallToolResult.fromContent(
          [TextContent(text: jsonEncode(devices))],
        );
      },
    );
