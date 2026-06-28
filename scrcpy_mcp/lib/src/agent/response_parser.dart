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

/// Structured result of parsing one autoglm-phone model reply.
sealed class ParsedResponse {
  const ParsedResponse({
    required this.think,
    required this.content,
    required this.memory,
  });

  /// Reasoning captured inside `<think></think>`, or '' when absent.
  final String think;

  /// Everything outside the `<think></think>` block with the `<think>` and
  /// `<memory>` blocks removed and `<answer>` unwrapped. This is what gets
  /// stored in assistant history.
  final String content;

  /// Content of the optional `<memory>` block, or '' when absent.
  final String memory;
}

/// A parseable action was found.
final class ParsedAction extends ParsedResponse {
  const ParsedAction({
    required super.think,
    required super.content,
    required super.memory,
    required this.action,
  });

  final PhoneAction action;
}

/// No usable action could be parsed; [reason] explains why.
final class ParseFailure extends ParsedResponse {
  const ParseFailure({
    required super.think,
    required super.content,
    required super.memory,
    required this.reason,
  });

  final String reason;
}

/// Parses autoglm-phone model output into a [ParsedResponse].
///
/// The model emits `<think>…</think>` reasoning followed by exactly one action:
/// `do(action="…", …)` or `finish(message="…")`, optionally wrapped in
/// `<answer>…</answer>` and possibly preceded by natural-language text.
class ResponseParser {
  static ParsedResponse parse(String text) {
    final (think, content, memory) = _split(text);

    if (content.trim().isEmpty) {
      return ParseFailure(
        think: think,
        content: content,
        memory: memory,
        reason: 'empty/think-only response',
      );
    }

    // finish(message="…") — matched greedily up to the final `")` so unescaped
    // inner quotes in the message don't truncate it.
    final finishMatch = RegExp(
      r'finish\s*\(\s*message\s*=\s*"(.*)"\s*\)',
      dotAll: true,
    ).firstMatch(content);
    if (finishMatch != null) {
      return ParsedAction(
        think: think,
        content: content,
        memory: memory,
        action: FinishAction(_unescape(finishMatch.group(1)!)),
      );
    }

    // do(action="…", …)
    final hasDo = RegExp(
      r'(?<![a-zA-Z])do\s*\(',
      dotAll: true,
    ).hasMatch(content);
    if (hasDo) {
      final action = _parseDo(content);
      if (action == null) {
        return ParseFailure(
          think: think,
          content: content,
          memory: memory,
          reason: 'malformed do(): could not extract action type',
        );
      }
      return ParsedAction(
        think: think,
        content: content,
        memory: memory,
        action: action,
      );
    }

    return ParseFailure(
      think: think,
      content: content,
      memory: memory,
      reason: 'no action token',
    );
  }

  /// Splits the raw reply into `(think, content, memory)`: pulls the
  /// `<think></think>` block out as `think`, pulls `<memory></memory>` as
  /// `memory`, and in the remainder unwraps `<answer></answer>` if present.
  /// `content` is that remainder, trimmed.
  static (String think, String content, String memory) _split(String text) {
    var think = '';
    final thinkMatch = RegExp(
      '<think>(.*?)</think>',
      dotAll: true,
    ).firstMatch(text);
    if (thinkMatch != null) think = thinkMatch.group(1)!.trim();

    var content = text.replaceAll(
      RegExp('<think>.*?</think>', dotAll: true),
      '',
    );

    var memory = '';
    final memoryMatch = RegExp(
      '<memory>(.*?)</memory>',
      dotAll: true,
    ).firstMatch(content);
    if (memoryMatch != null) {
      memory = memoryMatch.group(1)!.trim();
      content = content.replaceAll(
        RegExp('<memory>.*?</memory>', dotAll: true),
        '',
      );
    }

    final answerMatch = RegExp(
      r'<answer>\s*(.*?)\s*</answer>',
      dotAll: true,
    ).firstMatch(content);
    if (answerMatch != null) content = answerMatch.group(1)!;

    return (think, content.trim(), memory);
  }

  /// Parses the inside of a `do(...)` call into a [DoAction], or null if the
  /// action type is missing. Coordinate fields use a numeric regex; free-text
  /// fields use [_extractFreeText] to tolerate unescaped quotes.
  static DoAction? _parseDo(String content) {
    final action = _extractQuoted(content, 'action');
    if (action == null) return null;
    return DoAction(
      action: action,
      element: _extractIntList(content, 'element'),
      start: _extractIntList(content, 'start'),
      end: _extractIntList(content, 'end'),
      text: _extractFreeText(content, 'text'),
      app: _extractFreeText(content, 'app'),
      duration: _extractQuoted(content, 'duration'),
      // Call_API carries its payload under `instruction`; fold it into message
      // so the runner has a single field to read.
      message:
          _extractFreeText(content, 'message') ??
          _extractFreeText(content, 'instruction'),
    );
  }

  /// Extracts a short, well-formed quoted value (`key="value"`), honoring
  /// backslash escapes. Used for `action` and `duration`.
  static String? _extractQuoted(String content, String key) {
    final match = RegExp(
      '$key\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"',
    ).firstMatch(content);
    return match != null ? _unescape(match.group(1)!) : null;
  }

  /// Extracts a free-text field: everything after `key="` to the end of the
  /// call, stripping a trailing `")` (or lone `"`). Assumes the free-text field
  /// is the last argument of the `do(...)` call (true for autoglm output), which
  /// lets unescaped inner quotes pass through unharmed. The key must sit at an
  /// argument boundary (after `(` or `,`) so it can't prefix-match a longer key
  /// such as `subtext`. Returns null if absent.
  static String? _extractFreeText(String content, String key) {
    final match = RegExp('[(,]\\s*$key\\s*=\\s*"').firstMatch(content);
    if (match == null) return null;
    var rest = content.substring(match.end).trimRight();
    if (rest.endsWith('")')) {
      rest = rest.substring(0, rest.length - 2);
    } else if (rest.endsWith('"')) {
      rest = rest.substring(0, rest.length - 1);
    }
    return _unescape(rest);
  }

  static List<int>? _extractIntList(String content, String key) {
    final match = RegExp('$key\\s*=\\s*\\[([^\\]]*)\\]').firstMatch(content);
    if (match == null) return null;
    final ints = match
        .group(1)!
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
    return ints.isEmpty ? null : ints;
  }

  static String _unescape(String s) =>
      s.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
}
