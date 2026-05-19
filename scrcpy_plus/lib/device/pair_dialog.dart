import 'dart:io';

import 'package:logger_utils/logger_utils.dart';

final appLogger = Logger('scrcpy_plus');

/// Shows a native macOS dialog for device pairing input.
class PairDialog {
  /// Show dialog for IP:port input. Returns the address or null if cancelled.
  static Future<String?> showAddressDialog() async {
    try {
      const script =
          'display dialog "Enter device IP:port\n(e.g. 192.168.1.100:5555)" '
          'with title "Pair Device" default answer "" '
          'buttons {"Cancel", "Connect"} default button "Connect"';
      final result = await Process.run('osascript', ['-e', script]);

      if (result.exitCode != 0) return null;

      final output = result.stdout.toString();
      final match = RegExp('text returned:(.+)').firstMatch(output);
      return match?.group(1)?.trim();
    } catch (e) {
      appLogger.warning('Pair address dialog failed: $e');
      return null;
    }
  }

  /// Show dialog for pairing code input. Returns the code or null if cancelled.
  static Future<String?> showCodeDialog() async {
    try {
      const script =
          'display dialog "Enter 6-digit pairing code\n'
          '(from phone wireless debugging)" '
          'with title "Pairing Code" default answer "" '
          'buttons {"Cancel", "Pair"} default button "Pair"';
      final result = await Process.run('osascript', ['-e', script]);

      if (result.exitCode != 0) return null;

      final output = result.stdout.toString();
      final match = RegExp('text returned:(.+)').firstMatch(output);
      return match?.group(1)?.trim();
    } catch (e) {
      appLogger.warning('Pair code dialog failed: $e');
      return null;
    }
  }
}
