import 'dart:io';

/// Narrow interface for the parts of a [Process] used by recording logic.
abstract class RecordingProcess {
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// Snapshot of the current recording state.
class RecordingStatus {
  const RecordingStatus({
    required this.isRecording,
    this.deviceId,
    this.startTime,
    this.remotePath,
  });

  final bool isRecording;
  final String? deviceId;
  final DateTime? startTime;
  final String? remotePath;

  Map<String, dynamic> toJson() => {
    'is_recording': isRecording,
    if (deviceId != null) 'device_id': deviceId,
    if (startTime != null) 'start_time': startTime!.toUtc().toIso8601String(),
    if (remotePath != null) 'remote_path': remotePath,
  };
}

/// ADB operations required for screen recording.
abstract class RecordingAdb {
  /// Launches `adb shell screenrecord` in the background; does NOT await exit.
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  });

  /// Pulls a file from the device to the host.
  Future<void> pullFile(String deviceId, String remotePath, String localPath);

  /// Deletes a file on the device.
  Future<void> removeFile(String deviceId, String remotePath);
}
