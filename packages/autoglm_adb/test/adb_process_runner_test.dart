import 'package:autoglm_adb/src/adb_process_runner.dart';
import 'package:autoglm_adb/src/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdbProcessRunner', () {
    test('runs basic command successfully', () async {
      const runner = AdbProcessRunner();
      // 'echo' exists on macOS/Linux.
      final result = await runner.runRaw('echo', ['hello']);
      expect(result.exitCode, 0);
      expect(result.stdout.toString().trim(), 'hello');
    });

    test('throws AdbException on non-zero exit code', () async {
      const runner = AdbProcessRunner();
      try {
        await runner.runRaw('ls', ['/path-does-not-exist']);
        fail('Should have thrown AdbException');
      } on AdbException catch (e) {
        expect(e.message, contains('ls'));
      }
    });

    test('handles timeout', () async {
      const runner = AdbProcessRunner();
      try {
        await runner.runRaw(
          'sleep',
          [
            '2',
          ],
          timeout: const Duration(milliseconds: 100),
        );
        fail('Should have timed out');
      } on AdbException catch (e) {
        expect(e.message, contains('timeout'));
      }
    });
  });
}
