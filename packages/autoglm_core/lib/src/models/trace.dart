/// Represents a single trace span record.
class SpanRecord {
  /// Creates a new [SpanRecord].
  const SpanRecord({
    required this.traceId,
    required this.spanId,
    required this.name,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.durationMs,
    this.parentSpanId,
    this.attrs = const {},
    this.error,
  });

  /// The trace ID.
  final String traceId;

  /// The span ID.
  final String spanId;

  /// The parent span ID.
  final String? parentSpanId;

  /// The span name.
  final String name;

  /// The span status.
  final String status;

  /// The start time.
  final DateTime startTime;

  /// The end time.
  final DateTime endTime;

  /// The duration in milliseconds.
  final double durationMs;

  /// The span attributes.
  final Map<String, dynamic> attrs;

  /// The error message and type.
  final Map<String, String>? error;

  /// Converts the record to a JSON map.
  Map<String, dynamic> toJson() => {
    'trace_id': traceId,
    'span_id': spanId,
    if (parentSpanId != null) 'parent_span_id': parentSpanId,
    'name': name,
    'status': status,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'duration_ms': durationMs,
    'attrs': attrs,
    if (error != null) 'error': error,
  };
}

/// Represents a timing summary for a single trace.
class TraceTimingSummary {
  /// Creates a new [TraceTimingSummary].
  const TraceTimingSummary({
    required this.traceId,
    required this.steps,
    required this.totalDurationMs,
    required this.screenshotDurationMs,
    required this.currentAppDurationMs,
    required this.llmDurationMs,
    required this.parseActionDurationMs,
    required this.executeActionDurationMs,
    required this.updateContextDurationMs,
    required this.adbDurationMs,
    required this.sleepDurationMs,
    required this.otherDurationMs,
  });

  /// The trace ID.
  final String traceId;

  /// Number of steps in the trace.
  final int steps;

  /// Total duration in milliseconds.
  final double totalDurationMs;

  /// Duration of screenshot captures.
  final double screenshotDurationMs;

  /// Duration of app state checks.
  final double currentAppDurationMs;

  /// Duration of LLM calls.
  final double llmDurationMs;

  /// Duration of action parsing.
  final double parseActionDurationMs;

  /// Duration of action execution.
  final double executeActionDurationMs;

  /// Duration of context updates.
  final double updateContextDurationMs;

  /// Duration of ADB operations.
  final double adbDurationMs;

  /// Duration of sleep steps.
  final double sleepDurationMs;

  /// Duration of other operations.
  final double otherDurationMs;

  /// Converts the summary to a JSON map.
  Map<String, dynamic> toJson() => {
    'trace_id': traceId,
    'steps': steps,
    'total_duration_ms': totalDurationMs,
    'screenshot_duration_ms': screenshotDurationMs,
    'current_app_duration_ms': currentAppDurationMs,
    'llm_duration_ms': llmDurationMs,
    'parse_action_duration_ms': parseActionDurationMs,
    'execute_action_duration_ms': executeActionDurationMs,
    'update_context_duration_ms': updateContextDurationMs,
    'adb_duration_ms': adbDurationMs,
    'sleep_duration_ms': sleepDurationMs,
    'other_duration_ms': otherDurationMs,
  };
}
