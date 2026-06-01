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
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/src/scrcpy_mcp_adapters.dart';
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

      final processResult = await adb.shell([
        'am',
        'start',
        '-a',
        'android.intent.action.INSERT',
        '-t',
        'vnd.android.cursor.dir/contact',
      ], deviceId: realDevices.first);
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
      await adb.shell([
        'am',
        'start',
        '-a',
        'android.intent.action.INSERT',
        '-t',
        'vnd.android.cursor.dir/contact',
      ], deviceId: realDevices.first);
      await Future<void>.delayed(const Duration(seconds: 2));
      // Coordinates 540,1594 target the 名字 field on 1080×2340 Pixel devices.
      await adb.shell([
        'input',
        'tap',
        '540',
        '1594',
      ], deviceId: realDevices.first);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });

    setUp(() async {
      if (realDevices.isEmpty) return;
      await adb.shell([
        'input',
        'keyevent',
        'KEYCODE_CTRL_A',
      ], deviceId: realDevices.first);
      await adb.shell([
        'input',
        'keyevent',
        'KEYCODE_DEL',
      ], deviceId: realDevices.first);
      await Future<void>.delayed(const Duration(milliseconds: 200));
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

    Future<String> uiautomatorText() async {
      final result = await adb.shell([
        'sh',
        '-c',
        'uiautomator dump /sdcard/ui.xml && cat /sdcard/ui.xml',
      ], deviceId: realDevices.first);
      return result.stdout as String;
    }

    test(
      'inject_text — ASCII appears in focused input',
      () async {
        if (realDevices.isEmpty) {
          markTestSkipped('No Android device connected via ADB');
          return;
        }

        const text = 'hello';
        final textResult = await e2eEnv.client.callTool(
          const CallToolRequest(name: 'inject_text', arguments: {'text': text}),
        );
        expect(textResult.isError, isFalse, reason: textContent(textResult));

        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(await uiautomatorText(), contains(text));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'inject_text — Chinese text appears in focused input',
      () async {
        if (realDevices.isEmpty) {
          markTestSkipped('No Android device connected via ADB');
          return;
        }

        const text = '你好，最近怎么样？';
        final textResult = await e2eEnv.client.callTool(
          const CallToolRequest(name: 'inject_text', arguments: {'text': text}),
        );
        expect(textResult.isError, isFalse, reason: textContent(textResult));

        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(await uiautomatorText(), contains(text));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
