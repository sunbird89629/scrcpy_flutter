import 'dart:io';

import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';

/// Application-wide logger instance.
final _log = Logger('scrcpy_plus');

/// Launches and manages scrcpy as a subprocess.
class ScrcpyLauncher {
  ScrcpyLauncher({this.config = const ScrcpyConfig()});

  ScrcpyConfig config;
  Process? _process;

  bool get isRunning => _process != null;

  /// Launch scrcpy for the given device serial.
  Future<void> launch(String serial) async {
    if (_process != null) {
      _log.warning('scrcpy already running, killing previous instance');
      await kill();
    }

    final args = config.toArgs(serial);
    _log.info('Launching: ${config.scrcpyPath} ${args.join(' ')}');

    try {
      _process = await Process.start(config.scrcpyPath, args);
      _process!.exitCode.then((code) {
        _log.info('scrcpy exited with code $code');
        _process = null;
      });
    } catch (e) {
      _process = null;
      _log.severe('Failed to launch scrcpy: $e');
      rethrow;
    }
  }

  /// Launch scrcpy with flex virtual display for the given app package.
  /// Uses `--new-display -x --start-app=<package>` (requires scrcpy 4.0+).
  Future<void> launchFlex(String serial, String package) async {
    if (_process != null) {
      _log.warning('scrcpy already running, killing previous instance');
      await kill();
    }

    final args = [
      '--serial',
      serial,
      '--new-display',
      '-x',
      '--start-app=$package',
    ];
    _log.info('Launching flex: ${config.scrcpyPath} ${args.join(' ')}');

    try {
      _process = await Process.start(config.scrcpyPath, args);
      _process!.exitCode.then((code) {
        _log.info('scrcpy flex exited with code $code');
        _process = null;
      });
    } catch (e) {
      _process = null;
      _log.severe('Failed to launch flex scrcpy: $e');
      rethrow;
    }
  }

  /// Kill the running scrcpy process.
  Future<void> kill() async {
    _process?.kill();
    await _process?.exitCode;
    _process = null;
  }

  void dispose() {
    _process?.kill();
    _process = null;
  }
}
