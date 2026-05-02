import 'package:autoglm_logger/app_logger.dart';
import 'package:flutter/foundation.dart';

/// Adds a tagged logger to a class. Override [logTag] to provide a stable
/// name for release builds where `runtimeType` is obfuscated.
mixin ClassLogger {
  /// Logger tag used as the prefix for every message.
  @protected
  String get logTag => runtimeType.toString();

  /// Logs a debug message with [logTag].
  @protected
  void logD(String message) => appLogger.d('[$logTag] $message');

  /// Logs an info message with [logTag].
  @protected
  void logI(String message) => appLogger.i('[$logTag] $message');

  /// Logs a warning message with [logTag].
  @protected
  void logW(String message, [Object? error, StackTrace? stack]) =>
      appLogger.w('[$logTag] $message', error, stack);

  /// Logs an error message with [logTag].
  @protected
  void logE(String message, [Object? error, StackTrace? stack]) =>
      appLogger.e('[$logTag] $message', error, stack);
}
