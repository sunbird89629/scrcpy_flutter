/// Represents a single action the autoglm-phone model wants to execute.
sealed class PhoneAction {
  const PhoneAction();
}

final class DoAction extends PhoneAction {
  const DoAction({
    required this.action,
    this.element,
    this.start,
    this.end,
    this.text,
    this.app,
    this.duration,
    this.message,
  });

  final String action;
  final List<int>? element; // [x, y]
  final List<int>? start; // [x, y]
  final List<int>? end; // [x, y]
  final String? text;
  final String? app;
  final String? duration;
  final String? message;

  @override
  String toString() => 'DoAction($action)';
}

final class FinishAction extends PhoneAction {
  const FinishAction(this.message);
  final String message;

  @override
  String toString() => 'FinishAction($message)';
}

/// Parses autoglm-phone model output into [PhoneAction] objects.
///
/// The model outputs actions in two formats:
/// - `do(action="Tap", element=[500,100])`
/// - `finish(message="Done")`
///
/// Actions may appear inside `<answer>` tags or as standalone text.
class ActionParser {
  /// Extracts the first valid action from [text]. Returns null if no action
  /// is found.
  static PhoneAction? parse(String text) {
    // Try to extract content from <answer> tags first
    final answerMatch = RegExp(
      r'<answer>\s*(.*?)\s*</answer>',
      dotAll: true,
    ).firstMatch(text);
    final effectiveText = answerMatch?.group(1) ?? text;

    // Match finish(message="...")
    final finishMatch = RegExp(
      r'finish\s*\(\s*message\s*=\s*"((?:[^"\\]|\\.)*)"\s*\)',
    ).firstMatch(effectiveText);
    if (finishMatch != null) {
      return FinishAction(_unescape(finishMatch.group(1)!));
    }

    // Match do(action="...", ...)
    final doMatch = RegExp(r'do\s*\((.*)\)', dotAll: true)
        .firstMatch(effectiveText);
    if (doMatch == null) return null;

    final args = doMatch.group(1)!;
    final action = _extractString(args, 'action');
    if (action == null) return null;

    return DoAction(
      action: action,
      element: _extractIntList(args, 'element'),
      start: _extractIntList(args, 'start'),
      end: _extractIntList(args, 'end'),
      text: _extractString(args, 'text'),
      app: _extractString(args, 'app'),
      duration: _extractString(args, 'duration'),
      message: _extractString(args, 'message'),
    );
  }

  static String? _extractString(String text, String key) {
    final match = RegExp('$key\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"')
        .firstMatch(text);
    return match != null ? _unescape(match.group(1)!) : null;
  }

  static List<int>? _extractIntList(String text, String key) {
    final match = RegExp('$key\\s*=\\s*\\[([^\\]]*)\\]').firstMatch(text);
    if (match == null) return null;
    return match
        .group(1)!
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
  }

  static String _unescape(String s) =>
      s.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
}
