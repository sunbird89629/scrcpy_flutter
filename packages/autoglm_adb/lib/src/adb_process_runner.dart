import 'dart:async';
import 'dart:io';

import 'package:autoglm_adb/src/exceptions.dart';
import 'package:autoglm_logger/autoglm_logger.dart';

/// A wrapper around [Process.run] providing timeouts and
/// standard error handling.
class AdbProcessRunner {
  /// Creates a new [AdbProcessRunner].
  const AdbProcessRunner();

  /// Runs an executable with arguments. Throws [AdbException] on timeout
  /// or failure.
  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final result = await Process.run(executable, arguments).timeout(timeout);

      if (result.exitCode != 0) {
        final err = result.stderr.toString().trim();
        final out = result.stdout.toString().trim();
        appLogger.d(
          'Command failed ($executable ${arguments.join(' ')}):\n$err\n$out',
        );
        throw AdbException(
          'Command failed ($executable ${arguments.join(' ')}):\n$err\n$out',
        );
      }
      return result;
    } on TimeoutException {
      throw AdbException(
        'Command timeout after ${timeout.inSeconds}s '
        '($executable ${arguments.join(' ')})',
      );
    } on ProcessException catch (e) {
      throw AdbException('Failed to start process: ${e.message}');
    }
  }
}
