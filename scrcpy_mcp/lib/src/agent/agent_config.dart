class AgentConfig {
  const AgentConfig({
    this.maxSteps = 15,
    this.keepScreenshots = 3,
    this.stallThreshold = 3,
    this.repeatedActionThreshold = 10,
    this.screenSize,
    this.sopDir,
  });

  final int maxSteps;
  final (int, int)? screenSize;

  /// Base directory for the SOP memory store.
  /// Null disables the SOP feature entirely.
  final String? sopDir;

  /// How many of the most recent screenshots to keep in the LLM context.
  /// Older screenshots are dropped to stay within autoglm-phone's 20K window.
  /// Keep ≥3 so the model has enough consecutive frames to compare and notice
  /// when its actions stop changing the screen. The prompt has no explicit
  /// "stall after N identical screens" rule, so [stallThreshold] is the real
  /// backstop — see its doc below.
  final int keepScreenshots;

  /// Abort the task when the screen stays byte-identical for this many
  /// consecutive steps — actions are having no visible effect. Acts as a
  /// backstop for the model failing to self-detect a stall.
  final int stallThreshold;

  /// Abort when the exact same action repeats this many consecutive times — a
  /// loop where the screen keeps changing but the agent never converges (e.g.
  /// scrolling a long list forever). Much looser than [stallThreshold]: some
  /// repetition (scrolling through a list) is legitimate, so this must sit above
  /// any reasonable scroll budget a task prompt allows.
  final int repeatedActionThreshold;
}

class AgentResult {
  const AgentResult({
    required this.result,
    required this.steps,
    required this.success,
    this.trajectory = const [],
  });

  final String result;
  final int steps;
  final bool success;

  /// One-line summaries of the actions taken, oldest first. Used by SopWriter.
  final List<String> trajectory;

  AgentResult copyWith({List<String>? trajectory}) => AgentResult(
    result: result,
    steps: steps,
    success: success,
    trajectory: trajectory ?? this.trajectory,
  );
}
