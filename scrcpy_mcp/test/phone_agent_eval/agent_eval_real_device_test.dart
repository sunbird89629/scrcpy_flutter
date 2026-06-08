@Tags(['real-device'])
library;

import 'dart:io';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'agent_eval_result.dart';
import 'agent_eval_runner.dart';
import 'cases/youtube_history_recent.dart';

void main() {
  initLogging();

  test('real-device agent eval cases', () async {
    if (Platform.environment['SCRCPY_RUN_AGENT_EVAL'] != '1') {
      markTestSkipped('Set SCRCPY_RUN_AGENT_EVAL=1 to run agent eval cases.');
      return;
    }

    final adbClient = AdbClient();
    final adb = ScrcpyMcpAdb(adbClient);
    final devices = await adb.getDevices();
    if (devices.isEmpty) {
      markTestSkipped('No Android device connected via ADB.');
      return;
    }
    final deviceId = devices.first;
    final deviceInfo = await adbClient.getDeviceInfo(deviceId);
    final actionRunner = AdbActionRunner(
      adb: adb,
      deviceId: deviceId,
      size: (deviceInfo.screenWidth.round(), deviceInfo.screenHeight.round()),
    );
    final runner = AgentEvalRunner(
      outputRoot: Directory(
        'temp/agent_eval_runs/${DateTime.now().toIso8601String()}',
      ),
      deviceId: deviceId,
      adb: adb,
      chat: AutoGLMClient.fromTest().chat,
      screenshotProvider: () => adb.takeScreenshot(deviceId),
      actionRunner: actionRunner.run,
      deepLocate: true,
    );

    final cases = [
      // settingsNavigationCase,
      // twitterHomeCase,
      youtubeHistoryRecentCase,
    ];
    final results = <AgentEvalResult>[];
    for (final evalCase in cases) {
      results.add(await runner.runCase(evalCase));
    }

    expect(
      results.where((result) => !result.success),
      isEmpty,
      reason: results
          .map(
            (r) =>
                '${r.caseId}: ${r.success} ${r.failureKind} ${r.finalResult}',
          )
          .join('\n'),
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}
