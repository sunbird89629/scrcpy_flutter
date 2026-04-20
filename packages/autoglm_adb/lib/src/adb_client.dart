import 'dart:io';

import 'package:autoglm_adb/src/adb_process_runner.dart';
import 'package:autoglm_adb/src/exceptions.dart';

/// Provides high-level ADB commands.
class AdbClient {
  /// Creates a new [AdbClient].
  const AdbClient({
    this.adbPath = 'adb',
    this.runner = const AdbProcessRunner(),
  });

  /// The path to the adb executable.
  final String adbPath;

  /// The runner used to execute adb commands.
  final AdbProcessRunner runner;

  /// Checks if adb is accessible and returns its version string.
  Future<String> getVersion() async {
    final result = await runner.runRaw(adbPath, ['version']);
    return result.stdout.toString().trim();
  }

  /// Runs an adb shell command.
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final args = <String>[];
    if (deviceId != null) {
      args.addAll(['-s', deviceId]);
    }
    args
      ..add('shell')
      ..addAll(arguments);
    return runner.runRaw(adbPath, args, timeout: timeout);
  }

  /// Sets up an adb port forward.
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {
    final args = <String>[];
    if (deviceId != null) {
      args.addAll(['-s', deviceId]);
    }
    args.add('forward');
    if (noRebind) {
      args.add('--no-rebind');
    }
    args.addAll([local, remote]);
    await runner.runRaw(adbPath, args);
  }

  /// Removes an adb port forward.
  Future<void> forwardRemove(String local, {String? deviceId}) async {
    final args = <String>[];
    if (deviceId != null) {
      args.addAll(['-s', deviceId]);
    }
    args.addAll(['forward', '--remove', local]);
    await runner.runRaw(adbPath, args);
  }

  /// Pushes a file to the device.
  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) async {
    final args = <String>[];
    if (deviceId != null) {
      args.addAll(['-s', deviceId]);
    }
    args.addAll(['push', localPath, remotePath]);
    await runner.runRaw(adbPath, args);
  }

  /// Pairs a device using Android 11+ wireless debugging.
  /// Returns success message or throws [AdbException] on failure.
  Future<String> pair(String ip, int port, String code) async {
    if (code.length != 6 || int.tryParse(code) == null) {
      throw const AdbException('Pairing code must be 6 digits.');
    }

    final address = '$ip:$port';
    try {
      final result = await runner.runRaw(adbPath, ['pair', address, code]);
      final output =
          result.stdout.toString().trim() + result.stderr.toString().trim();

      if (output.toLowerCase().contains('successfully paired') ||
          output.toLowerCase().contains('success')) {
        return 'Successfully paired to $address';
      }
      throw AdbException('Pairing failed: $output');
    } catch (e) {
      if (e is AdbException) {
        final msg = e.message.toLowerCase();
        if (msg.contains('pairing code')) {
          throw const AdbException('Invalid pairing code');
        } else if (msg.contains('refused')) {
          throw const AdbException(
            'Connection refused - check if wireless debugging is enabled',
          );
        }
      }
      rethrow;
    }
  }

  /// Connects to a previously paired device or an open ADB port.
  Future<String> connect(String ip, int port) async {
    final address = '$ip:$port';
    final result = await runner.runRaw(adbPath, ['connect', address]);
    final output = result.stdout.toString().trim();

    if (output.contains('connected to $address') ||
        output.contains('already connected')) {
      return output;
    }
    throw AdbException('Connect failed: $output');
  }

  /// Lists connected devices.
  Future<List<String>> devices() async {
    final result = await runner.runRaw(adbPath, ['devices']);
    final lines = result.stdout.toString().split('\n');
    final devices = <String>[];

    // First line is "List of devices attached"
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty && line.contains('\t')) {
        devices.add(line.split('\t').first);
      }
    }
    return devices;
  }
}
