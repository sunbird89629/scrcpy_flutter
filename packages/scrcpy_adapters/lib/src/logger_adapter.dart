import 'package:autoglm_logger/autoglm_logger.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// Adapts [appLogger] to the [ScrcpyLogger] interface.
class AppLoggerAdapter implements ScrcpyLogger {
  /// Creates a logger adapter that forwards to [appLogger].
  const AppLoggerAdapter();

  @override
  void debug(String message) => appLogger.d(message);

  @override
  void info(String message) => appLogger.i(message);

  @override
  void warn(String message, [Object? error, StackTrace? stack]) =>
      appLogger.w(message, error, stack);

  @override
  void error(String message, [Object? error, StackTrace? stack]) =>
      appLogger.e(message, error, stack);
}
