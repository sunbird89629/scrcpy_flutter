// Real-device end-to-end tests for inject_* MCP tools.
// These tests require a physical Android device connected via ADB and use a
// real ScrcpySessionImpl for end-to-end verification.
//
// Run manually:
//   dart test test/scrcpy_mcp_real_device_inject_controls_test.dart --tags real-device

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

  group('real device — inject controls (e2e)', () {
    late ScrcpySessionImpl e2eSession;
    late RealDeviceE2eEnv e2eEnv;
    late (int, int) screenSize;

    setUpAll(() async {
      if (realDevices.isEmpty) return;
      final deviceId = realDevices.first;
      e2eSession = await ScrcpySessionImpl.create(adb: adb);
      e2eEnv = RealDeviceE2eEnv(adb: adb, session: e2eSession);
      await e2eEnv.connect();
      await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': deviceId},
        ),
      );
      screenSize = await getScreenSize(adb, deviceId);
      // Force-stop Settings so re-launch reliably resets scroll to the top.
      await adb.shell([
        'am',
        'force-stop',
        'com.android.settings',
      ], deviceId: realDevices.first);
      await adb.shell([
        'am',
        'start',
        '-a',
        'android.settings.SETTINGS',
      ], deviceId: realDevices.first);
      // Wait long enough for Settings RecyclerView to finish initial layout
      // before scroll events. A short wait can cause scroll events to be
      // dropped because the view tree is still settling.
      await Future<void>.delayed(const Duration(milliseconds: 3000));
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

    test(
      'inject_swipe changes screen content',
      () async {
        if (realDevices.isEmpty) {
          markTestSkipped('No Android device connected via ADB');
          return;
        }
        final (w, h) = screenSize;

        final before = screenshotBytes(
          await e2eEnv.client.callTool(
            const CallToolRequest(name: 'take_screenshot'),
          ),
        );

        // Swipe up from bottom-third to top-third = scroll content down.
        final swipeResult = await e2eEnv.client.callTool(
          CallToolRequest(
            name: 'inject_swipe',
            arguments: {
              'x1': w ~/ 2,
              'y1': h * 2 ~/ 3,
              'x2': w ~/ 2,
              'y2': h ~/ 3,
              'width': w,
              'height': h,
              'durationMs': 400,
              'steps': 24,
            },
          ),
        );
        expect(swipeResult.isError, isFalse, reason: textContent(swipeResult));

        // Wait for fling/inertia to settle.
        await Future<void>.delayed(const Duration(milliseconds: 1500));

        final after = screenshotBytes(
          await e2eEnv.client.callTool(
            const CallToolRequest(name: 'take_screenshot'),
          ),
        );

        expect(
          hasScreenChanged(before, after),
          isTrue,
          reason: 'Screen should change after swipe',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('inject_scroll succeeds', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }
      final (w, h) = screenSize;

      // Weak assertion: scrcpy's inject_scroll generates MotionEvent.ACTION_SCROLL
      // (mouse wheel), which Android Settings RecyclerView does not reliably
      // respond to — most Android apps only handle touch swipes (ACTION_MOVE).
      // Visual verification is therefore unreliable; assert only that the call
      // succeeds. Binary protocol encoding is verified by control_message_test.
      final scrollResult = await e2eEnv.client.callTool(
        CallToolRequest(
          name: 'inject_scroll',
          arguments: {
            'x': w ~/ 2,
            'y': h ~/ 2,
            'width': w,
            'height': h,
            'hScroll': 0,
            'vScroll': 16,
          },
        ),
      );
      expect(scrollResult.isError, isFalse, reason: textContent(scrollResult));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
      'inject_key Home navigates to launcher',
      () async {
        if (realDevices.isEmpty) {
          markTestSkipped('No Android device connected via ADB');
          return;
        }

        final before = screenshotBytes(
          await e2eEnv.client.callTool(
            const CallToolRequest(name: 'take_screenshot'),
          ),
        );

        // Android KEYCODE_HOME requires DOWN+UP to trigger navigation.
        final downResult = await e2eEnv.client.callTool(
          const CallToolRequest(
            name: 'inject_key',
            arguments: {'keycode': 3, 'action': 0},
          ),
        );
        expect(downResult.isError, isFalse, reason: textContent(downResult));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final upResult = await e2eEnv.client.callTool(
          const CallToolRequest(
            name: 'inject_key',
            arguments: {'keycode': 3, 'action': 1},
          ),
        );
        expect(upResult.isError, isFalse, reason: textContent(upResult));

        await Future<void>.delayed(const Duration(milliseconds: 800));

        final after = screenshotBytes(
          await e2eEnv.client.callTool(
            const CallToolRequest(name: 'take_screenshot'),
          ),
        );

        expect(
          hasScreenChanged(before, after),
          isTrue,
          reason: 'Home key should trigger navigation or launcher animation',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'inject_touch at centre succeeds',
      () async {
        if (realDevices.isEmpty) {
          markTestSkipped('No Android device connected via ADB');
          return;
        }
        final (w, h) = screenSize;

        final downResult = await e2eEnv.client.callTool(
          CallToolRequest(
            name: 'inject_touch',
            arguments: {
              'x': w ~/ 2,
              'y': h ~/ 2,
              'width': w,
              'height': h,
              'action': 0, // ScrcpyAction.down
            },
          ),
        );
        expect(downResult.isError, isFalse, reason: textContent(downResult));

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final upResult = await e2eEnv.client.callTool(
          CallToolRequest(
            name: 'inject_touch',
            arguments: {
              'x': w ~/ 2,
              'y': h ~/ 2,
              'width': w,
              'height': h,
              'action': 1, // ScrcpyAction.up
            },
          ),
        );
        expect(upResult.isError, isFalse, reason: textContent(upResult));

        await Future<void>.delayed(const Duration(milliseconds: 400));

        // Weak assertion: log screenshot size for debugging, no pixel-diff required.
        // Tapping empty space produces no guaranteed visual change.
        final after = screenshotBytes(
          await e2eEnv.client.callTool(
            const CallToolRequest(name: 'take_screenshot'),
          ),
        );
        printOnFailure('inject_touch screenshot size: ${after.length} bytes');
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
