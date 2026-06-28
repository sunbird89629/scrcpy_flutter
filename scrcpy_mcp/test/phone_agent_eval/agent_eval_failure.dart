enum AgentEvalFailureKind {
  parseFailure,
  maxSteps,
  stalled,
  repeatedAction,
  humanRequired,
  toolError,
  textAssertionFailed,
  visualAssertionFailed,
  unknown,
}

AgentEvalFailureKind classifyAgentFailure(String result) {
  if (result.contains('Could not parse an action')) {
    return AgentEvalFailureKind.parseFailure;
  }
  if (result.contains('Max steps')) {
    return AgentEvalFailureKind.maxSteps;
  }
  if (result.contains('screen unchanged') || result.contains('unchanged')) {
    return AgentEvalFailureKind.stalled;
  }
  if (result.contains('repeated the same action')) {
    return AgentEvalFailureKind.repeatedAction;
  }
  if (result.contains('requires human')) {
    return AgentEvalFailureKind.humanRequired;
  }
  return AgentEvalFailureKind.unknown;
}
