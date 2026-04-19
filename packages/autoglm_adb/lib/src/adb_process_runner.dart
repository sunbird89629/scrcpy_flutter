import 'dart:async';
import 'dart:io';

/// Exception thrown by [AdbProcessRunner] when a command fails.
class AdbException implements Exception {
  /// Creates a new [AdbException] with the given [message].
  const AdbException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'AdbException: $message';
}

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
