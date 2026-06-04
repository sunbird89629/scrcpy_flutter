import 'dart:io';

import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';

final appLogger = Logger('scrcpy_plus');

/// Shows a simple macOS dialog for editing scrcpy settings.
/// Uses osascript for native dialog since we have no Flutter window.
class SettingsDialog {
  static Future<ScrcpyConfig?> show(ScrcpyConfig current) async {
    try {
      // Show current values and ask for new ones via osascript
      final lines = [
        'scrcpy path: ${current.scrcpyPath}',
        'Max size: ${current.maxSize}',
        'Video bit rate: ${current.videoBitRate}',
        'Video codec: ${current.videoCodec}',
      ].join(r'\n');
      final message =
          'display dialog "$lines" with title "scrcpy_plus Settings" buttons {"OK"} default button "OK"';
      final result = await Process.run('osascript', ['-e', message]);

      if (result.exitCode == 0) {
        // For MVP, just return current config unchanged.
        // A proper implementation would parse user input from the dialog.
        return current;
      }
      return null;
    } catch (e) {
      appLogger.warning('Settings dialog failed: $e');
      return null;
    }
  }
}
