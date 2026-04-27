import 'package:autoglm_core/autoglm_core.dart';
import 'package:flutter/foundation.dart';

/// Adds a tagged logger to a class. Override [logTag] to provide a stable
/// name for release builds where `runtimeType` is obfuscated.
mixin ClassLogger {
  @protected
  String get logTag => runtimeType.toString();

  @protected
  void logD(String message) => appLogger.d('[$logTag] $message');

  @protected
  void logI(String message) => appLogger.i('[$logTag] $message');

  @protected
  void logW(String message, [Object? error, StackTrace? stack]) =>
      appLogger.w('[$logTag] $message', error, stack);

  @protected
  void logE(String message, [Object? error, StackTrace? stack]) =>
      appLogger.e('[$logTag] $message', error, stack);
}
