/// Call-site tracing for [Logger]: logs a function's arguments and return value.
library;

import 'package:logging/logging.dart';

/// Maximum recursion depth for [dumpValue]; deeper structures collapse to `...`.
const _maxDumpDepth = 4;

/// One indentation step used when rendering lists across multiple lines.
const _indentStep = '   ';

/// Adds [trace] / [traceAsync] helpers that log argument and return values.
///
/// Tracing is a debug tool: it emits at [Level.FINE], so it only produces
/// output while verbose/debug logging is enabled. When FINE is not loggable
/// the call runs with **zero** formatting overhead — no [dumpValue] work is
/// done and the original function is invoked directly. Real error logging is
/// unaffected since it uses higher levels (e.g. [Logger.severe]).
extension LoggerTrace on Logger {
  /// Runs [call], logging `name(args)` before and `name => result` after.
  ///
  /// Pass the values to print as [args] and the real invocation as [call];
  /// the call site stays unchanged otherwise:
  ///
  /// ```dart
  /// final title = log.trace(
  ///   'formatTitle',
  ///   [raw, locale],
  ///   () => formatTitle(raw, locale),
  /// );
  /// ```
  T trace<T>(String name, List<Object?> args, T Function() call) {
    if (!isLoggable(Level.FINE)) return call();
    fine('$name(${_dumpArgs(args)})');
    final result = call();
    fine('$name => ${dumpValue(result)}');
    return result;
  }

  /// Async variant of [trace]: awaits [call] before logging the return value.
  Future<T> traceAsync<T>(
    String name,
    List<Object?> args,
    Future<T> Function() call,
  ) async {
    if (!isLoggable(Level.FINE)) return call();
    fine('$name(${_dumpArgs(args)})');
    final result = await call();
    fine('$name => ${dumpValue(result)}');
    return result;
  }
}

String _dumpArgs(List<Object?> args) =>
    [for (final a in args) dumpValue(a)].join(', ');

/// Renders [value] as a human-readable string for trace logs.
///
/// - Lists/iterables → multi-line, indented, wrapped in `[...]`, no indices.
/// - Maps → inline `{ k: v }`.
/// - Strings → quoted.
/// - Everything else → `toString()`.
///
/// Recursion is bounded by [_maxDumpDepth]; an identity [seen] set guards
/// against cyclic references so self-referential structures don't loop.
String dumpValue(Object? value, {int depth = 0, Set<Object>? seen}) {
  if (value == null) return 'null';
  if (value is String) return '"$value"';
  if (value is num || value is bool) return value.toString();
  if (depth >= _maxDumpDepth) return '...';

  seen ??= Set<Object>.identity();

  if (value is Map) {
    if (!seen.add(value)) return '{...}';
    final body = value.entries
        .map(
          (e) =>
              '${e.key}: ${dumpValue(e.value, depth: depth + 1, seen: seen)}',
        )
        .join(', ');
    seen.remove(value);
    return body.isEmpty ? '{}' : '{ $body }';
  }

  if (value is Iterable) {
    if (!seen.add(value)) return '[...]';
    final items = value
        .map((e) => dumpValue(e, depth: depth + 1, seen: seen))
        .toList();
    seen.remove(value);
    if (items.isEmpty) return '[]';
    final indent = _indentStep * (depth + 1);
    final close = _indentStep * depth;
    return '[\n${items.map((i) => '$indent$i').join(',\n')}\n$close]';
  }

  return value.toString();
}
