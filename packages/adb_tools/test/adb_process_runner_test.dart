import 'package:adb_tools/src/adb_process_runner.dart';
import 'package:adb_tools/src/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('AdbProcessRunnerImpl', () {
    test('run returns result on success', () async {
      const runner = AdbProcessRunnerImpl();
      final result = await runner.run('echo', ['hello']);
      expect(result.exitCode, 0);
      expect(result.stdout.toString().trim(), 'hello');
    });

    test('run does not throw on non-zero exit code', () async {
      const runner = AdbProcessRunnerImpl();
      final result = await runner.run('ls', ['/path-does-not-exist']);
      expect(result.exitCode, isNot(0));
    });

    test('run throws AdbException on timeout', () async {
      const runner = AdbProcessRunnerImpl();
      await expectLater(
        runner.run('sleep', ['2'], timeout: const Duration(milliseconds: 100)),
        throwsA(
          isA<AdbException>().having(
            (e) => e.message,
            'message',
            contains('timeout'),
          ),
        ),
      );
    });

    test('run throws AdbException on missing binary', () async {
      const runner = AdbProcessRunnerImpl();
      await expectLater(
        runner.run('/nonexistent/binary', ['--version']),
        throwsA(isA<AdbException>()),
      );
    });
  });
}
