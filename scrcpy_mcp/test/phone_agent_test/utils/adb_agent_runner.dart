// Shared adb-driven action runner for real-device agent e2e tests.
//
// This is a plain library (not a *_test.dart), so `dart test` skips it. Import
// it from real-device test files to run an autoglm-phone task with one call.
//
// All device control goes through `adb shell input` (see [AdbActionRunner]) —
// no scrcpy session needed.

import 'package:adb_tools/adb_tools.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

/// Runs [task] on a real device via autoglm-phone, driving the device entirely
/// through `adb shell`. Returns the agent's [AgentResult].
Future<AgentResult> runAgentTask({
  required AdbClient adb,
  required String task,
  required String deviceId,
  int maxSteps = 15,
}) async {
  final (screenWidth, screenHeight) = await adb.getDeviceScreenInfo(deviceId);
  final runner = AdbActionRunner(
    adb: ScrcpyMcpAdb(adb),
    deviceId: deviceId,
    size: (screenWidth.toInt(), screenHeight.toInt()),
  );
  final agent = PhoneAgent(
    config: AgentConfig(maxSteps: maxSteps),
    client: AutoGLMOfficialClient.fromTest(),
    takeScreenshot: blankRetryingScreenshot(() => adb.takeScreenshot(deviceId)),
    actionRunner: runner.run,
  );
  return agent.run(task);
}
