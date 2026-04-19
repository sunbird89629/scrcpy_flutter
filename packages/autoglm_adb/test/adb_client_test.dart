import 'dart:io';

import 'package:autoglm_adb/src/adb_client.dart';
import 'package:autoglm_adb/src/adb_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRunner extends AdbProcessRunner {
  const FakeRunner(
    this.stdoutResponse, [
    this.exitCode = 0,
    this.stderrResponse = '',
  ]);
  final String stdoutResponse;
  final String stderrResponse;
  final int exitCode;

  @override
  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (exitCode != 0) {
      throw const AdbException('Command failed');
    }
    return ProcessResult(0, exitCode, stdoutResponse, stderrResponse);
  }
}

void main() {
  group('AdbClient', () {
    test('pair validates 6 digit code', () async {
      const client = AdbClient(runner: FakeRunner(''));
      expect(
        () => client.pair('192.168.1.1', 5555, '123'),
        throwsA(isA<AdbException>()),
      );
    });

    test('pair success parses output', () async {
      const client = AdbClient(
        runner: FakeRunner('Successfully paired to 192.168.1.1:5555 [guid]'),
      );
      final res = await client.pair('192.168.1.1', 5555, '123456');
      expect(res, contains('Successfully paired'));
    });

    test('devices parses output correctly', () async {
      const stdout = '''
List of devices attached
192.168.1.1:5555\tdevice
emulator-5554\toffline
''';
      const client = AdbClient(runner: FakeRunner(stdout));
      final devices = await client.devices();
      expect(devices, ['192.168.1.1:5555', 'emulator-5554']);
    });
  });
}
