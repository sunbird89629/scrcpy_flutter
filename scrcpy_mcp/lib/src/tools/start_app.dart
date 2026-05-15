import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

import '../mcp_tool.dart';

/// Launches an app on the device by Android package name.
///
/// Uses scrcpy's start-app control message (type 16), which calls
/// `PackageManager.getLaunchIntentForPackage()` on the device.
/// Requires an active mirroring session.
class StartAppTool extends McpTool {
  StartAppTool(this._session);
  final ScrcpySession _session;

  @override
  String get name => 'start_app';

  @override
  String get description =>
      'Launch an app on the device by package name '
      '(e.g. com.android.settings, com.android.chrome). '
      'Use adb shell pm list packages to discover installed packages.';

  @override
  final ToolInputSchema inputSchema = JsonSchema.object(
    properties: {
      'package': JsonSchema.string(
        description: 'Android package name of the app to launch',
      ),
    },
    required: ['package'],
  );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    if (!_session.isConnected) return McpTool.notConnectedResult;
    final pkg = args['package'] as String;
    _session.sendControlMessage(ScrcpyStartAppMessage(pkg));
    return CallToolResult.fromContent(
      [TextContent(text: 'App launched: $pkg')],
    );
  }
}
