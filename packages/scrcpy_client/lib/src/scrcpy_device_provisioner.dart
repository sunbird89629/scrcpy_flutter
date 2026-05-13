import 'package:scrcpy_client/src/scrcpy_server_options.dart';

/// Manages the lifecycle of a scrcpy server on an Android device.
///
/// Implementations handle: pushing the server JAR to the device,
/// setting up port forwarding, launching the on-device process,
/// and cleaning up those resources on stop.
abstract class ScrcpyDeviceProvisioner {
  String get deviceId;
  int get port;
  int get actualPort;
  ScrcpyServerOptions get options;

  /// Pushes the JAR, sets up forwarding, and starts the on-device process.
  Future<void> provision();

  /// Kills the on-device process and removes port forwarding.
  Future<void> depovision();
}
