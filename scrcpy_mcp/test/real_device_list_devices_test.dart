// Real-device integration tests for list_devices MCP tool.
//
// Run manually:
//   dart test test/scrcpy_mcp_real_device_list_devices_test.dart --tags real-device

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

  group('real device — list_devices', () {
    test('returns the connected device serial', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final env = RealDeviceEnv(adb: adb);
      await env.connect();

      final result = await env.client.callTool(
        const CallToolRequest(name: 'list_devices'),
      );

      expect(result.isError, isFalse);
      final devices = jsonDecode(textContent(result)) as List;
      expect(devices, unorderedEquals(realDevices));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
