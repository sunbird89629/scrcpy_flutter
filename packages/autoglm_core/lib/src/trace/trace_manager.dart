import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:autoglm_core/src/models/trace.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Manages trace spans and persistence.
class TraceManager {
  /// Creates a new [TraceManager].
  TraceManager({required this.logsDir});

  /// The directory where trace logs are stored.
  final String logsDir;
  final _uuid = const Uuid();

  final _spanStack = <String>[];
  String? _currentTraceId;

  /// Returns the active trace identifier.
  String? get currentTraceId => _currentTraceId;

  /// Returns the current span identifier.
  String? get currentSpanId => _spanStack.isNotEmpty ? _spanStack.last : null;

  /// Starts a new trace.
  void startTrace([String? traceId]) {
    _currentTraceId = traceId ?? _uuid.v4();
    _spanStack.clear();
  }

  /// Ends the active trace.
  void endTrace() {
    _currentTraceId = null;
    _spanStack.clear();
  }

  /// Starts a new span within the active trace.
  String startSpan(String name, {Map<String, dynamic>? attrs}) {
    if (_currentTraceId == null) startTrace();

    final spanId = _uuid.v4().substring(0, 16);
    _spanStack.add(spanId);
    return spanId;
  }

  /// Ends a span and records it to file.
  Future<void> endSpan(
    String spanId, {
    required String name,
    required DateTime startTime,
    required DateTime endTime,
    Map<String, dynamic>? attrs,
    Object? error,
  }) async {
    if (_spanStack.isEmpty || _spanStack.last != spanId) {
      _spanStack.remove(spanId);
    } else {
      _spanStack.removeLast();
    }

    final record = SpanRecord(
      traceId: _currentTraceId ?? 'unknown',
      spanId: spanId,
      name: name,
      status: error == null ? 'ok' : 'error',
      startTime: startTime,
      endTime: endTime,
      durationMs: endTime.difference(startTime).inMicroseconds / 1000.0,
      attrs: attrs ?? {},
      error: error != null ? {'message': error.toString()} : null,
    );

    await _writeRecord(record);
  }

  Future<void> _writeRecord(SpanRecord record) async {
    final date = DateTime.now().toIso8601String().split('T').first;
    final file = File(p.join(logsDir, 'trace_$date.jsonl'));

    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }

    final line = jsonEncode(record.toJson());
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }
}
