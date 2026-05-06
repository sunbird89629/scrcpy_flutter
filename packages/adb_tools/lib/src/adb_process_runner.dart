import 'dart:async';
import 'dart:io';

import 'package:adb_tools/src/exceptions.dart';
import 'package:autoglm_logger/autoglm_logger.dart';

/// Abstract base for running ADB processes.
///
/// [run] returns [ProcessResult] and never throws on non-zero exit codes.
/// Throws [AdbException] on timeout or process-level failures (e.g. binary not found).
abstract class AdbProcessRunner {
  const AdbProcessRunner();

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  });
}

/// Default implementation using [Process.run].
class AdbProcessRunnerImpl extends AdbProcessRunner {
  static final _log = Logger('autoglm.adb.AdbProcessRunner');
  const AdbProcessRunnerImpl();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final result = await Process.run(executable, arguments).timeout(timeout);
      _log.fine(_formatResult([executable, ...arguments].join(' '), result));
      return result;
    } on TimeoutException {
      throw AdbException(
        'timeout: ${[executable, ...arguments].join(' ')} '
        'exceeded ${timeout.inMilliseconds}ms',
      );
    } on ProcessException catch (e) {
      throw AdbException('Process failed: $e');
    }
  }

  static String _formatResult(String command, ProcessResult r) {
    final buf = StringBuffer();
    buf.writeln();
    buf.writeln('=' * 30);
    buf.writeln('command:');
    buf.writeln(command);
    buf.writeln('exit code: ${r.exitCode}');
    buf.writeln('stdout:');
    buf.writeln(r.stdout.toString());
    buf.writeln('stderr:');
    buf.writeln(r.stderr.toString());
    buf.writeln('-' * 30);
    return buf.toString();
  }
}
