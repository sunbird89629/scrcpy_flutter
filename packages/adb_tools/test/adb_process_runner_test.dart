import 'dart:io';

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

  group('AdbProcessRunnerImpl.formatResultLine', () {
    test('success without stderr → single line with exit code', () {
      final r = ProcessResult(123, 0, 'ok', '');
      expect(
        AdbProcessRunnerImpl.formatResultLine('adb shell input tap 1 2', r),
        'adb shell input tap 1 2 → exit 0',
      );
    });

    test('non-empty stderr is appended', () {
      final r = ProcessResult(123, 1, '', 'boom');
      expect(
        AdbProcessRunnerImpl.formatResultLine('adb x', r),
        'adb x → exit 1 | stderr: boom',
      );
    });

    test('no decorative block or ProcessResult dump', () {
      final line = AdbProcessRunnerImpl.formatResultLine(
        'cmd',
        ProcessResult(1, 0, '', ''),
      );
      expect(line, isNot(contains('>>>>')));
      expect(line, isNot(contains('Instance of')));
      expect(line.split('\n'), hasLength(1));
    });

    test('multiline stderr is flattened to one line', () {
      final r = ProcessResult(1, 1, '', 'error: device offline\nWaiting...');
      final line = AdbProcessRunnerImpl.formatResultLine('adb x', r);
      expect(line.split('\n'), hasLength(1));
      expect(line, 'adb x → exit 1 | stderr: error: device offline Waiting...');
    });

    test('whitespace-only stderr is treated as absent', () {
      final r = ProcessResult(1, 0, '', '   \n  ');
      expect(
        AdbProcessRunnerImpl.formatResultLine('adb x', r),
        'adb x → exit 0',
      );
    });
  });
}
