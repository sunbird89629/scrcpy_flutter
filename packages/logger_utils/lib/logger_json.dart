/// JSON-aware logging for [Logger]: pretty-prints payloads as indented JSON.
library;

import 'dart:convert';

import 'package:logging/logging.dart';

// Falls back to toString() for any object the encoder can't handle, so
// prettyJson never throws on unexpected payloads.
const _encoder = JsonEncoder.withIndent('  ', _stringify);

Object _stringify(Object? value) => '$value';

/// Renders [value] as indented JSON for logs.
///
/// - [Map]/[List] (or any JSON-encodable object) → 2-space indented JSON.
/// - [String] → parsed as JSON then re-indented; returned as-is if it is
///   not valid JSON.
/// - Anything not encodable → `toString()`.
///
/// Non-ASCII text (e.g. Chinese) is kept verbatim — Dart's encoder does not
/// escape it to `\uXXXX`. This never throws.
String prettyJson(Object? value) {
  var decoded = value;
  if (value is String) {
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return value;
    }
  }
  return _encoder.convert(decoded);
}

/// Adds [infoJson] for logging a message alongside a pretty-printed payload.
extension LoggerJson on Logger {
  /// Logs [message] at [Level.INFO], appending [payload] as indented JSON on
  /// the next line. [payload] may be a JSON-encodable object or a JSON string.
  void infoJson(String message, Object? payload) =>
      info('$message\n${prettyJson(payload)}');
}
