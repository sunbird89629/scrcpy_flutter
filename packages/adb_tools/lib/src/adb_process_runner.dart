import 'dart:async';
import 'dart:io';

import 'package:adb_tools/src/exceptions.dart';
import 'package:logger_utils/logger_utils.dart';

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
  static final _log = Logger('adb_tools.AdbProcessRunner');
  const AdbProcessRunnerImpl();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final result = await Process.run(executable, arguments).timeout(timeout);
      _log.fine(formatResultLine([executable, ...arguments].join(' '), result));
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

  /// One-line FINE log of a finished ADB process: `<command> → exit <code>`,
  /// with stderr appended when non-empty. Internal newlines in stderr are
  /// flattened to spaces so the entry stays on one line.
  ///
  /// Assumes system-encoding (String) stdout/stderr — the default for
  /// `Process.run`, which is what [run] uses. Raw-bytes (`List<int>`) stderr
  /// would stringify as a byte list; not a concern for the current call site.
  ///
  /// Package-internal (lives in `src/`, not exported) but non-private so it can
  /// be unit-tested directly.
  static String formatResultLine(String command, ProcessResult r) {
    final stderr = ((r.stderr as Object?)?.toString() ?? '').trim().replaceAll(
      '\n',
      ' ',
    );
    return stderr.isEmpty
        ? '$command → exit ${r.exitCode}'
        : '$command → exit ${r.exitCode} | stderr: $stderr';
  }
}
