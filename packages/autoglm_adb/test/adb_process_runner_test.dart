import 'package:autoglm_adb/src/adb_process_runner.dart';
import 'package:autoglm_adb/src/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdbProcessRunnerImpl', () {
    test('runRaw returns result on success', () async {
      const runner = AdbProcessRunnerImpl();
      final result = await runner.runRaw('echo', ['hello']);
      expect(result.exitCode, 0);
      expect(result.stdout.toString().trim(), 'hello');
    });

    test('runRaw does not throw on non-zero exit code', () async {
      const runner = AdbProcessRunnerImpl();
      final result = await runner.runRaw('ls', ['/path-does-not-exist']);
      expect(result.exitCode, isNot(0));
    });

    test('run throws AdbException on non-zero exit code', () async {
      const runner = AdbProcessRunnerImpl();
      expect(
        () => runner.run('ls', ['/path-does-not-exist']),
        throwsA(isA<AdbException>()),
      );
    });

    test('runRaw throws AdbException on timeout', () async {
      const runner = AdbProcessRunnerImpl();
      expect(
        () => runner.runRaw(
          'sleep',
          ['2'],
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<AdbException>().having((e) => e.message, 'message', contains('timeout')),
        ),
      );
    });

    test('run throws AdbException on timeout', () async {
      const runner = AdbProcessRunnerImpl();
      expect(
        () => runner.run(
          'sleep',
          ['2'],
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<AdbException>().having((e) => e.message, 'message', contains('timeout')),
        ),
      );
    });
  });
}
