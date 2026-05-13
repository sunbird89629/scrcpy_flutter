// Real-device integration tests for take_screenshot MCP tool.
//
// Run manually:
//   dart test test/scrcpy_mcp_real_device_take_screenshot_test.dart --tags real-device

@Tags(['real-device'])
library;

import 'dart:convert';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/app_logger.dart';
import 'package:mcp_dart/mcp_dart.dart';
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

  group('real device — take_screenshot', () {
    test('returns a valid PNG from the first connected device', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final env = RealDeviceEnv(adb: adb);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'take_screenshot'),
      );

      expect(result.isError, isFalse);
      final img = result.content.first as ImageContent;
      expect(img.mimeType, 'image/png');

      final bytes = base64Decode(img.data);
      // PNG magic: 89 50 4E 47 0D 0A 1A 0A
      expect(
        bytes.sublist(0, 4),
        equals([0x89, 0x50, 0x4E, 0x47]),
        reason: 'First 4 bytes must be PNG magic',
      );
      expect(bytes.length, greaterThan(64));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('explicit invalid device_id returns error', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final env = RealDeviceEnv(adb: adb);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(
          name: 'take_screenshot',
          arguments: {'device_id': 'invalid-device-serial-xyz'},
        ),
      );

      expect(result.isError, isTrue);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
