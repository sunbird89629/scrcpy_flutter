/// Application-wide logging configuration.
library;

// ignore_for_file: avoid_print, Console output is the primary sink for this logger.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart';

StreamSubscription<LogRecord>? _subscription;

/// True in debug mode, false in release.
const _debugMode = bool.fromEnvironment('dart.vm.product') == false;

/// Configures the root logger with console and optional file output.
///
/// Safe to call multiple times — subsequent calls reconfigure.
///
/// - In debug mode, root level is [Level.FINE].
/// - In release mode, root level is [Level.INFO].
/// - When [logsDir] is provided, logs are written to daily-rotated files
///   named `autoglm-YYYY-MM-DD.log`. Old files are pruned to the 5 most
///   recent by modification time.
void initLogging({String? logsDir}) {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = _debugMode ? Level.FINE : Level.INFO;

  final dir = logsDir != null ? Directory(logsDir) : null;
  if (dir != null && !dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  _pruneOldFiles(dir);

  _subscription?.cancel();
  _subscription = Logger.root.onRecord.listen((record) {
    _consoleSink(record);
    _fileSink(record, dir);
  });
}

void _consoleSink(LogRecord record) {
  final time = record.time.toIso8601String().substring(11, 23); // HH:mm:ss.SSS
  final level = record.level.name.padRight(7);
  final name = record.loggerName;
  final msg = '[$time] $level $name: ${record.message}';

  if (record.level >= Level.SEVERE) {
    print('\x1B[31m$msg\x1B[0m'); // red
  } else if (record.level >= Level.WARNING) {
    print('\x1B[33m$msg\x1B[0m'); // yellow
  } else if (record.level >= Level.INFO) {
    print(msg);
  } else {
    print('\x1B[90m$msg\x1B[0m'); // gray for debug/fine
  }

  if (record.error != null) {
    print('  ${record.error}');
  }
  if (record.stackTrace != null) {
    print('  ${record.stackTrace}');
  }
}

void _fileSink(LogRecord record, Directory? dir) {
  if (dir == null) return;
  try {
    final today = DateTime.now();
    final fileName = 'autoglm-${_dateStamp(today)}.log';
    final file = File(join(dir.path, fileName));
    final buffer = StringBuffer()
      ..write(record.time.toIso8601String())
      ..write(' ${record.level.name.padRight(7)} ')
      ..write(record.loggerName)
      ..write(': ')
      ..writeln(record.message);
    if (record.error != null) {
      buffer.writeln('  ${record.error}');
    }
    if (record.stackTrace != null) {
      buffer.writeln('  ${record.stackTrace}');
    }
    file.writeAsStringSync(buffer.toString(), mode: FileMode.append);
  } on Object {
    // File logging must not crash the app
  }
}

void _pruneOldFiles(Directory? dir) {
  if (dir == null || !dir.existsSync()) return;
  try {
    final files =
        dir
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
        // best-effort pruning
      }
    }
  } on Object {
    // best-effort listSync
  }
}

String _dateStamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}
