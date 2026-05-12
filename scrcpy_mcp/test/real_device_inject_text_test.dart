// Real-device end-to-end tests for inject_text MCP tool.
// These tests require a physical Android device connected via ADB and use a
// real ScrcpySessionImpl for end-to-end verification.
//
// Run manually:
//   dart test test/real_device_inject_text_test.dart --tags real-device

@Tags(['real-device'])
library;

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/app_logger.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_adapters.dart';
import 'package:scrcpy_view/scrcpy_core.dart';
import 'package:test/test.dart';

import 'real_device_test_utils.dart';

void main() {
  late ScrcpyMcpAdb adb;
  late List<String> realDevices;

  initLogging();

  setUpAll(() async {
    adb = ScrcpyMcpAdb(AdbClient());
    realDevices = await adb.getDevices();
  });

  group('real_device_test_adb', () {
    test('open_add_contact_page', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final processResult = await adb.shell(
        ['am', 'start', '-a', 'android.intent.action.INSERT', '-t', 'vnd.android.cursor.dir/contact'],
        deviceId: realDevices.first,
      );
      expect(processResult.exitCode, 0);
    });
  });

  group('real device — inject_text (e2e)', () {
    late ScrcpySessionImpl e2eSession;
    late RealDeviceE2eEnv e2eEnv;

    setUpAll(() async {
      if (realDevices.isEmpty) return;
      e2eSession = await ScrcpySessionImpl.create(adb: adb);
      e2eEnv = RealDeviceE2eEnv(adb: adb, session: e2eSession);
      await e2eEnv.connect();
      await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': realDevices.first},
        ),
      );
    });

    tearDownAll(() async {
      if (realDevices.isEmpty) return;
      try {
        await e2eEnv.client.callTool(
          const CallToolRequest(name: 'stop_mirroring'),
        );
      } catch (_) {
        // Transport may already be closed; ignore cleanup errors.
      }
    });

    test('inject_text succeeds', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      // Weak assertion: inject_text requires a focused input field to produce
      // visible output. Without a forced screen state, only success is checked.
      final textResult = await e2eEnv.client.callTool(
        const CallToolRequest(
          name: 'inject_text',
          arguments: {'text': 'hello'},
        ),
      );
      expect(textResult.isError, isFalse, reason: textContent(textResult));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('inject_text-chinese_text', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      // Weak assertion: inject_text requires a focused input field to produce
      // visible output. Without a forced screen state, only success is checked.
      final textResult = await e2eEnv.client.callTool(
        const CallToolRequest(
          name: 'inject_text',
          arguments: {'text': '你好，你好，最近怎么样？'},
        ),
      );
      expect(textResult.isError, isFalse, reason: textContent(textResult));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
