// Real-device integration tests for recording MCP tools
// (start_recording, stop_recording).
//
// Run manually:
//   dart test test/scrcpy_mcp_real_device_recording_test.dart --tags real-device

@Tags(['real-device'])
library;

import 'dart:convert';
import 'dart:io';

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

  group('real device — recording', () {
    late String deviceId;
    late RealDeviceEnv env;
    String? pulledPath;

    setUp(() async {
      if (realDevices.isEmpty) return;
      deviceId = realDevices.first;
      env = RealDeviceEnv(adb: adb, enableRecording: true);
      await env.connect();

      // Activate the mock session so start_recording is allowed
      await env.client.callTool(
        CallToolRequest(
          name: 'start_mirroring',
          arguments: {'device_id': deviceId},
        ),
      );
    });

    tearDown(() async {
      if (pulledPath != null) {
        final f = File(pulledPath!);
        if (f.existsSync()) await f.delete();
        pulledPath = null;
      }
    });

    test('start_recording succeeds and returns device path', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      final result = await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );
      addTearDown(() async {
        await env.client.callTool(
          const CallToolRequest(name: 'stop_recording'),
        );
      });

      expect(result.isError, isFalse, reason: textContent(result));
      final json = jsonDecode(textContent(result)) as Map<String, dynamic>;
      expect(json['status'], 'recording');
      expect(json['path_on_device'], contains('.mp4'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('stop_recording pulls video file to local disk', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      await env.client.callTool(const CallToolRequest(name: 'start_recording'));

      // Record for a short moment so the file is non-empty
      await Future<void>.delayed(const Duration(seconds: 3));

      final stopResult = await env.client.callTool(
        const CallToolRequest(name: 'stop_recording'),
      );

      expect(stopResult.isError, isFalse, reason: textContent(stopResult));
      final json = jsonDecode(textContent(stopResult)) as Map<String, dynamic>;
      expect(json['status'], 'finished');

      pulledPath = json['local_path'] as String;
      expect(pulledPath, endsWith('.mp4'));

      final file = File(pulledPath!);
      expect(file.existsSync(), isTrue,
          reason: 'File should exist at $pulledPath');
      expect(json['size_bytes'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('double start_recording returns error', () async {
      if (realDevices.isEmpty) {
        markTestSkipped('No Android device connected via ADB');
        return;
      }

      await env.client.callTool(const CallToolRequest(name: 'start_recording'));
      addTearDown(() async {
        await env.client.callTool(
          const CallToolRequest(name: 'stop_recording'),
        );
      });

      final result = await env.client.callTool(
        const CallToolRequest(name: 'start_recording'),
      );

      expect(result.isError, isTrue);
      expect(textContent(result), contains('Already recording'));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
