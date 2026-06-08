import 'agent_eval_failure.dart';

class AgentEvalAssertionResult {
  const AgentEvalAssertionResult({
    required this.kind,
    required this.passed,
    required this.reason,
  });

  final String kind;
  final bool passed;
  final String reason;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'passed': passed,
    'reason': reason,
  };
}

class AgentEvalResult {
  const AgentEvalResult({
    required this.caseId,
    required this.success,
    required this.failureKind,
    required this.finalResult,
    required this.steps,
    required this.duration,
    required this.assertions,
  });

  final String caseId;
  final bool success;
  final AgentEvalFailureKind? failureKind;
  final String finalResult;
  final int steps;
  final Duration duration;
  final List<AgentEvalAssertionResult> assertions;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'success': success,
    'failureKind': failureKind?.name,
    'finalResult': finalResult,
    'steps': steps,
    'durationMs': duration.inMilliseconds,
    'assertions': assertions.map((a) => a.toJson()).toList(),
  };
}
