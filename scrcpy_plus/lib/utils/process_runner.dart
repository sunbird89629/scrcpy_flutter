import 'dart:io';

/// Wrapper around [Process.run] for testability.
class ProcessRunner {
  const ProcessRunner();

  Future<ProcessResult> run(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }

  Future<Process> start(
    String executable,
    List<String> arguments,
  ) {
    return Process.start(executable, arguments);
  }
}
