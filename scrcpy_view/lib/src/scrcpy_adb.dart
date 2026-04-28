import 'dart:io';

/// Abstract ADB operations required by the scrcpy protocol.
///
/// Package consumers implement this using their own ADB client
/// (e.g., `autoglm_adb`'s `AdbClient`).
abstract class ScrcpyAdb {
  /// Path to the ADB executable.
  String get adbPath;

  /// List connected device serials.
  Future<List<String>> getDevices();

  /// Run a shell command on the device.
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  });

  /// Forward a local TCP port to a remote abstract socket.
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  });

  /// Remove a forward.
  Future<void> forwardRemove(String local, {String? deviceId});

  /// Push a file to the device.
  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  });
}
