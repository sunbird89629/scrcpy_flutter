import 'package:autoglm_core/src/trace/trace_manager.dart';

/// Context-manager helper for recording a trace span.
class TraceSpan {
  /// Creates a new [TraceSpan].
  TraceSpan(this._manager, this.name, {this.attrs});

  final TraceManager _manager;

  /// The span name.
  final String name;

  /// The span attributes.
  final Map<String, dynamic>? attrs;

  late final String _spanId;
  late final DateTime _startTime;

  /// Runs [body] inside a new trace span.
  Future<T> run<T>(Future<T> Function() body) async {
    _startTime = DateTime.now();
    _spanId = _manager.startSpan(name, attrs: attrs);

    try {
      final result = await body();
      await _manager.endSpan(
        _spanId,
        name: name,
        startTime: _startTime,
        endTime: DateTime.now(),
        attrs: attrs,
      );
      return result;
    } catch (e) {
      await _manager.endSpan(
        _spanId,
        name: name,
        startTime: _startTime,
        endTime: DateTime.now(),
        attrs: attrs,
        error: e,
      );
      rethrow;
    }
  }
}
