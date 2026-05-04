/// Logging sink for scrcpy operations.
///
/// Package consumers wire this to their own logging infrastructure
/// (e.g., `autoglm_logger`'s `initLogging()` or a no-op).
abstract class ScrcpyLogger {
  /// Debug-level message.
  void debug(String message);

  /// Info-level message.
  void info(String message);

  /// Warning-level message with optional error and stack trace.
  void warn(String message, [Object? error, StackTrace? stack]);

  /// Error-level message with optional error and stack trace.
  void error(String message, [Object? error, StackTrace? stack]);
}

/// No-op logger for when logging is not needed.
class NoOpScrcpyLogger implements ScrcpyLogger {
  /// Creates a no-op logger.
  const NoOpScrcpyLogger();

  @override
  void debug(String _) {}

  @override
  void info(String _) {}

  @override
  void warn(String _, [Object? __, StackTrace? ___]) {}

  @override
  void error(String _, [Object? __, StackTrace? ___]) {}
}
