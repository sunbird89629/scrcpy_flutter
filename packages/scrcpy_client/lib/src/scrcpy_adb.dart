import 'dart:io';
import 'dart:typed_data';

/// Abstract ADB operations required by the scrcpy protocol.
///
/// Package consumers implement this using their own ADB client
/// (e.g., `adb_tools`'s `AdbClient`).
abstract class ScrcpyAdb {
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
  Future<void> push(String localPath, String remotePath, {String? deviceId});

  /// Capture a screenshot of the device as raw PNG bytes.
  /// Uses `adb exec-out screencap -p` for binary output.
  Future<Uint8List> takeScreenshot(String deviceId);

  /// Start a long-running adb process and return its handle.
  ///
  /// [arguments] are the full adb argument list (e.g. `['-s', id, 'shell', ...]`).
  Future<Process> startProcess(List<String> arguments);
}
