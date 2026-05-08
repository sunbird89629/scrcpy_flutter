/// Pure Dart exports from scrcpy_view — no Flutter/dart:ui dependency.
///
/// Import this barrel in pure-Dart consumers (e.g. CLI tools, MCP servers)
/// that need the scrcpy protocol, ADB abstraction, and session management
/// without any Flutter dependency.
library;

export 'src/control_message.dart';
export 'src/scrcpy_adb.dart';
export 'src/scrcpy_logger.dart';
export 'src/scrcpy_packet.dart';
export 'src/scrcpy_server.dart';
export 'src/scrcpy_session.dart';
export 'src/scrcpy_session_impl.dart';
