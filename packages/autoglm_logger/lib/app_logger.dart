import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart';

/// Application-wide logger. Initialize once via [initAppLogger]; subsequent
/// access through the top-level [appLogger] singleton.
///
/// Writes to stdout AND a daily-rotated file under the `logsDir` passed at
/// construction time. Files are named `autoglm-YYYY-MM-DD.log`. Old files
/// are pruned to the most recent 5 by mtime.
class AppLogger {
  /// Creates an [AppLogger] that optionally writes to [logsDir].
  /// If [logsDir] is null, it only writes to console.
  AppLogger(Directory? logsDir) : _logsDir = logsDir {
    final outputs = <LogOutput>[ConsoleOutput()];

    if (_logsDir != null) {
      if (!_logsDir.existsSync()) {
        _logsDir.createSync(recursive: true);
      }
      final today = DateTime.now();
      final fileName = 'autoglm-${_dateStamp(today)}.log';
      _file = File(join(_logsDir.path, fileName));
      outputs.add(_FileOutput(_file!));
      _pruneOldFiles();
    }

    _logger = Logger(
      level: kDebugMode ? Level.all : Level.info,
      printer: SimplePrinter(
        colors: stdout.hasTerminal,
        printTime: true,
      ),
      output: MultiOutput(outputs),
    );
  }

  final Directory? _logsDir;
  File? _file;
  late final Logger _logger;

  static AppLogger? _instance;

  /// Whether [initAppLogger] has been called in this isolate.
  static bool get isInitialized => _instance != null;

  /// Logs a debug-level message.
  void d(Object message, [Object? error, StackTrace? stack]) =>
      _logger.d(message, error: error, stackTrace: stack);

  /// Logs an info-level message.
  void i(Object message, [Object? error, StackTrace? stack]) =>
      _logger.i(message, error: error, stackTrace: stack);

  /// Alias for [i].
  void info(Object message, [Object? error, StackTrace? stack]) =>
      i(message, error, stack);

  /// Logs a warning-level message.
  void w(Object message, [Object? error, StackTrace? stack]) =>
      _logger.w(message, error: error, stackTrace: stack);

  /// Alias for [w].
  void warning(Object message, [Object? error, StackTrace? stack]) =>
      w(message, error, stack);

  /// Logs an error-level message with optional [error] and [stack].
  void e(Object message, [Object? error, StackTrace? stack]) =>
      _logger.e(message, error: error, stackTrace: stack);

  /// Alias for [e].
  void error(Object message, [Object? error, StackTrace? stack]) =>
      e(message, error, stack);

  /// Forces buffered output to disk.
  Future<void> flush() async {
    await _logger.close();
  }

  /// Logs an info message if initialized, otherwise does nothing.
  static void maybeLog(Object message) {
    _instance?.i(message);
  }

  /// Logs an error message if initialized, otherwise does nothing.
  static void maybeError(Object message, [Object? error, StackTrace? stack]) {
    _instance?.e(message, error, stack);
  }

  void _pruneOldFiles() {
    if (_logsDir == null) return;
    try {
      final files = _logsDir
          .listSync()
          .whereType<File>()
          .where((f) => basename(f.path).startsWith('autoglm-'))
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
      for (final f in files.skip(5)) {
        try {
          f.deleteSync();
        } on Object {
          // best-effort pruning; failure here is non-critical
        }
      }
    } on Object {
      // best-effort listSync
    }
  }

  static String _dateStamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }
}

/// Initializes the global [appLogger]. Safe to call multiple times in the same
/// isolate — subsequent calls overwrite the singleton.
///
/// If [logsDir] is null, logs will only be printed to the terminal.
void initAppLogger({String? logsDir}) {
  AppLogger._instance = AppLogger(logsDir != null ? Directory(logsDir) : null);
}

/// Top-level logger singleton. Throws a [StateError] if called before
/// [initAppLogger].
AppLogger get appLogger {
  final inst = AppLogger._instance;
  if (inst == null) {
    throw StateError(
      'appLogger accessed before initAppLogger() was called',
    );
  }
  return inst;
}

class _FileOutput extends LogOutput {
  _FileOutput(this._file);

  final File _file;

  @override
  void output(OutputEvent event) {
    final content = event.lines.map((l) => '$l\n').join();
    try {
      _file.writeAsStringSync(content, mode: FileMode.append);
    } on Object {
      // File logging must not crash the app
    }
  }
}
