import 'action_parser.dart';

// PhoneAction 类型暂留在 action_parser.dart，Task 3 再迁入本文件。
export 'action_parser.dart' show DoAction, FinishAction, PhoneAction;

/// Structured result of parsing one autoglm-phone model reply.
sealed class ParsedResponse {
  const ParsedResponse({required this.think, required this.content});

  /// Reasoning captured inside `<think></think>`, or '' when absent.
  final String think;

  /// Everything outside the `<think></think>` block: any untagged reasoning
  /// plus the action token. This is what gets stored in assistant history.
  final String content;
}

/// A parseable action was found.
final class ParsedAction extends ParsedResponse {
  const ParsedAction({
    required super.think,
    required super.content,
    required this.action,
  });

  final PhoneAction action;
}

/// No usable action could be parsed; [reason] explains why.
final class ParseFailure extends ParsedResponse {
  const ParseFailure({
    required super.think,
    required super.content,
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
    final (think, content) = _split(text);

    if (content.trim().isEmpty) {
      return ParseFailure(
        think: think,
        content: content,
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
        action: FinishAction(_unescape(finishMatch.group(1)!)),
      );
    }

    // do(action="…", …)
    final hasDo = RegExp(
      r'do\s*\(',
      dotAll: true,
    ).hasMatch(content);
    if (hasDo) {
      final action = _parseDo(content);
      if (action == null) {
        return ParseFailure(
          think: think,
          content: content,
          reason: 'malformed do(): could not extract action type',
        );
      }
      return ParsedAction(think: think, content: content, action: action);
    }

    return ParseFailure(
      think: think,
      content: content,
      reason: 'no action token',
    );
  }

  /// Splits the raw reply into `(think, content)`: pulls the `<think></think>`
  /// block out as think and, if present, unwraps `<answer></answer>` in the
  /// remainder. content is the remainder with the think block removed.
  static (String think, String content) _split(String text) {
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

    final answerMatch = RegExp(
      r'<answer>\s*(.*?)\s*</answer>',
      dotAll: true,
    ).firstMatch(content);
    if (answerMatch != null) content = answerMatch.group(1)!;

    return (think, content.trim());
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
      message: _extractFreeText(content, 'message') ??
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
  /// lets unescaped inner quotes pass through unharmed. Returns null if absent.
  static String? _extractFreeText(String content, String key) {
    final marker = '$key="';
    final idx = content.indexOf(marker);
    if (idx == -1) return null;
    var rest = content.substring(idx + marker.length).trimRight();
    if (rest.endsWith('")')) {
      rest = rest.substring(0, rest.length - 2);
    } else if (rest.endsWith('"')) {
      rest = rest.substring(0, rest.length - 1);
    }
    return _unescape(rest);
  }

  static List<int>? _extractIntList(String content, String key) {
    final match =
        RegExp('$key\\s*=\\s*\\[([^\\]]*)\\]').firstMatch(content);
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
