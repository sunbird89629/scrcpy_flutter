import 'dart:async';
import 'dart:io';

import 'package:adb_tools/src/exceptions.dart';
import 'package:autoglm_logger/autoglm_logger.dart';

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
  static final _log = Logger('AdbTools.AdbProcessRunnerImpl');
  const AdbProcessRunnerImpl();

  @override
  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _log.info([executable, ...arguments].join(' '));
    final result = await Process.run(executable, arguments).timeout(timeout);
    _log.info(result.toString());
    return result;
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return runRaw(executable, arguments, timeout: timeout);
  }
}
