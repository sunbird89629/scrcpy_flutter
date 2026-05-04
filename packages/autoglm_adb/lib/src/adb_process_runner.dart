import 'dart:async';
import 'dart:io';

import 'package:autoglm_adb/src/exceptions.dart';

/// Abstract base for running ADB processes.
///
/// Two contract levels:
/// - [runRaw] — always returns [ProcessResult]; never throws on non-zero exit.
/// - [run] — throws [AdbException] when exit code is non-zero.
abstract class AdbProcessRunner {
  const AdbProcessRunner();

  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  });

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  });
}

/// Default implementation using [Process.run].
class AdbProcessRunnerImpl extends AdbProcessRunner {
  const AdbProcessRunnerImpl();

  @override
  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await Process.run(executable, arguments).timeout(timeout);
    } on TimeoutException {
      throw AdbException(
        'Command timeout after ${timeout.inSeconds}s '
        '($executable ${arguments.join(' ')})',
      );
    } on ProcessException catch (e) {
      throw AdbException('Failed to start process: ${e.message}');
    }
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await runRaw(executable, arguments, timeout: timeout);
    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      final out = result.stdout.toString().trim();
      throw AdbException(
        'Command failed ($executable ${arguments.join(' ')}):\n$err\n$out',
      );
    }
    return result;
  }
}
