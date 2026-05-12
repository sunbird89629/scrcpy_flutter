import 'dart:io';

import 'package:adb_tools/src/adb_client.dart';
import 'package:adb_tools/src/adb_process_runner.dart';
import 'package:adb_tools/src/exceptions.dart';
import 'package:test/test.dart';

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
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return ProcessResult(0, exitCode, stdoutResponse, stderrResponse);
  }
}

void main() {
  group('AdbClient', () {
    test('pair validates 6 digit code', () async {
      final client = AdbClient(runner: const FakeRunner(''));
      await expectLater(
        client.pair('192.168.1.1', 5555, '123'),
        throwsA(isA<AdbException>()),
      );
    });

    test('pair success parses output', () async {
      final client = AdbClient(
        runner:
            const FakeRunner('Successfully paired to 192.168.1.1:5555 [guid]'),
      );
      final res = await client.pair('192.168.1.1', 5555, '123456');
      expect(res, contains('Successfully paired'));
    });

    test('pair throws on connection refused', () async {
      final client = AdbClient(
        runner: const FakeRunner('', 1, 'error: Connection refused'),
      );
      await expectLater(
        client.pair('192.168.1.1', 5555, '123456'),
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            contains('Connection refused'),
          ),
        ),
      );
    });

    test('devices parses output correctly', () async {
      const stdout = '''
List of devices attached
192.168.1.1:5555\tdevice
emulator-5554\toffline
''';
      final client = AdbClient(runner: const FakeRunner(stdout));
      final devices = await client.getDevices();
      expect(devices, ['192.168.1.1:5555', 'emulator-5554']);
    });

    test('shell returns result even on non-zero exit code', () async {
      final client = AdbClient(runner: const FakeRunner('error output', 1));
      final result = await client.shell(['ls', '/nonexistent']);
      expect(result.exitCode, 1);
      expect(result.stdout.toString(), 'error output');
    });
  });
}
