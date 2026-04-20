import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

/// Application logger.
class AppLogger {
  AppLogger._(this.logger);
  final Logger logger;
  static AppLogger? _instance;

  /// Returns true if the logger is initialized.
  static bool get isInitialized => _instance != null;

  /// Initializes the logger.
  static void init({required String logsDir}) {
    final fileOutput = FileOutput(
      file: File(p.join(logsDir, 'app.log')),
    );
    _instance = AppLogger._(
      Logger(output: MultiOutput([ConsoleOutput(), fileOutput])),
    );
  }

  /// Returns the singleton instance.
  static AppLogger get instance {
    if (_instance == null) throw StateError('AppLogger not initialized');
    return _instance!;
  }

  /// Logs an info message.
  void info(String message) => logger.i(message);

  /// Logs an error message.
  void error(String message, [dynamic e, StackTrace? s]) =>
      logger.e(message, error: e, stackTrace: s);

  /// Helper for logging info.
  void i(String message) => info(message);

  /// Conditional log helper.
  void maybeLog(String message) {
    if (isInitialized) info(message);
  }

  /// Flushes the log.
  Future<void> flush() async {}
}

/// Helper for initializing logger.
void initAppLogger({required String logsDir}) =>
    AppLogger.init(logsDir: logsDir);

/// Global logger instance.
AppLogger get appLogger => AppLogger.instance;
