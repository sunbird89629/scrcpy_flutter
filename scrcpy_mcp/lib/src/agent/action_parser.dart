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
/// The model outputs actions in several formats:
/// - `do(action="Tap", element=[500,100])` — explicit keyword args
/// - `Tap([500,300])` — shorthand positional arg
/// - `Launch("Chrome")` — single string arg
/// - `screenshot(message="Done")` — finish with message
/// - `finish(message="Done")` — finish with message
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

    // 1. finish(message="...") / 2. screenshot(message="...") — finish variants.
    // The model frequently emits *unescaped* inner quotes in the message, e.g.
    //   finish(message="否，未出现"Twitter（X）"。")
    // so the body is matched greedily up to the final `")` rather than the
    // first inner quote (which would truncate/garble the message).
    final finishMatch = RegExp(
      r'(?:finish|screenshot)\s*\(\s*message\s*=\s*"(.*)"\s*\)',
      dotAll: true,
    ).firstMatch(effectiveText);
    if (finishMatch != null) {
      return FinishAction(_unescape(finishMatch.group(1)!));
    }

    // 3. do(action="...", ...)
    final doMatch = RegExp(r'do\s*\((.*)\)', dotAll: true)
        .firstMatch(effectiveText);
    if (doMatch != null) {
      return _parseDoArgs(doMatch.group(1)!);
    }

    // 4. Shorthand FunctionName(args) — the most common format from the API
    return _parseShorthand(effectiveText);
  }

  /// Parse `action="Tap", element=[500,300], ...` from a do() call.
  static DoAction? _parseDoArgs(String args) {
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

  /// Parse `FunctionName("arg")` or `FunctionName([1,2])` shorthand.
  ///
  /// Examples:
  /// - `Launch("Chrome")` → DoAction(action: "Launch", app: "Chrome")
  /// - `Tap([500,300])` → DoAction(action: "Tap", element: [500,300])
  /// - `Back()` → DoAction(action: "Back")
  static PhoneAction? _parseShorthand(String text) {
    final match = RegExp(r'(\w+)\s*\((.*)\)', dotAll: true).firstMatch(text);
    if (match == null) return null;

    final name = match.group(1)!;
    final rawArgs = match.group(2)!.trim();

    // Parse positional args: strings, int lists, or nothing
    final args = <dynamic>[];
    if (rawArgs.isNotEmpty) {
      // Split by comma, but respect nested brackets
      for (final part in _splitArgs(rawArgs)) {
        final trimmed = part.trim();
        // Int list: [500, 300]
        final listMatch = RegExp(r'^\[([^\]]*)\]$').firstMatch(trimmed);
        if (listMatch != null) {
          final ints = listMatch
              .group(1)!
              .split(',')
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>()
              .toList();
          if (ints.isNotEmpty) {
            args.add(ints);
            continue;
          }
        }
        // String: "value" or key="value"
        final strMatch = RegExp(r'^(?:\w+\s*=\s*)?\"((?:[^"\\]|\\.)*)\"$')
            .firstMatch(trimmed);
        if (strMatch != null) {
          args.add(_unescape(strMatch.group(1)!));
          continue;
        }
        // Raw word: value (without quotes)
        if (trimmed.isNotEmpty) {
          args.add(trimmed);
        }
      }
    }

    // Map function name → DoAction or FinishAction
    return _mapShorthand(name, args);
  }

  static PhoneAction _mapShorthand(String name, List<dynamic> args) {
    // Actions whose first positional arg is a coordinate pair
    switch (name) {
      case 'Tap':
        return DoAction(
          action: 'Tap',
          element: args.isNotEmpty && args[0] is List<int>
              ? args[0] as List<int>
              : null,
        );
      case 'Long Press':
        return DoAction(
          action: 'Long Press',
          element: args.isNotEmpty && args[0] is List<int>
              ? args[0] as List<int>
              : null,
        );
      case 'Double Tap':
        return DoAction(
          action: 'Double Tap',
          element: args.isNotEmpty && args[0] is List<int>
              ? args[0] as List<int>
              : null,
        );
      case 'Swipe':
        return DoAction(
          action: 'Swipe',
          start: args.isNotEmpty && args[0] is List<int>
              ? args[0] as List<int>
              : null,
          end: args.length > 1 && args[1] is List<int>
              ? args[1] as List<int>
              : null,
        );
      case 'Type':
        return DoAction(
          action: 'Type',
          text: args.isNotEmpty && args[0] is String ? args[0] as String : null,
        );
      case 'Launch':
        return DoAction(
          action: 'Launch',
          app: args.isNotEmpty && args[0] is String ? args[0] as String : null,
        );
      case 'Wait':
        return DoAction(
          action: 'Wait',
          duration:
              args.isNotEmpty && args[0] is String ? args[0] as String : null,
        );
      case 'Take_over':
        return DoAction(
          action: 'Take_over',
          message:
              args.isNotEmpty && args[0] is String ? args[0] as String : null,
        );
      case 'Back':
        return const DoAction(action: 'Back');
      case 'Home':
        return const DoAction(action: 'Home');
      case 'screenshot':
      case 'finish':
        return FinishAction(
          args.isNotEmpty && args[0] is String ? args[0] as String : 'Done',
        );
      default:
        // Unknown function — treat as DoAction with the function name as the
        // action type and first arg as fallback.
        return DoAction(
          action: name,
          app: args.isNotEmpty && args[0] is String ? args[0] as String : null,
          text: args.isNotEmpty && args[0] is String ? args[0] as String : null,
        );
    }
  }

  /// Split `"Chrome", [500,300], key="value"` into top-level parts, respecting
  /// nested brackets.
  static List<String> _splitArgs(String text) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      switch (text[i]) {
        case '(':
        case '[':
          depth++;
        case ')':
        case ']':
          depth--;
        case ',':
          if (depth == 0) {
            parts.add(text.substring(start, i));
            start = i + 1;
          }
      }
    }
    if (start < text.length) {
      parts.add(text.substring(start));
    }
    return parts;
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
