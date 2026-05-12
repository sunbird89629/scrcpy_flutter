import 'dart:io';

import 'package:logger_utils/logger_utils.dart';

import 'recording_adb.dart';

final _log = Logger('scrcpy.recording');

class RecordingController {
  RecordingController(this._adb);

  final RecordingAdb _adb;
  RecordingProcess? _process;
  String? _deviceId;
  String? _remotePath;
  DateTime? _startTime;

  bool get isRecording => _process != null;

  RecordingStatus get status => RecordingStatus(
        isRecording: isRecording,
        deviceId: _deviceId,
        startTime: _startTime,
        remotePath: _remotePath,
      );

  Future<String> start(
    String deviceId, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    if (isRecording) {
      throw StateError('Already recording on $_deviceId since $_startTime');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final remotePath = '/sdcard/mcp_rec_$timestamp.mp4';
    final process = await _adb.startScreenrecord(
      deviceId,
      remotePath,
      bitrate: bitrate,
      maxTime: maxTime,
    );
    _process = process;
    _deviceId = deviceId;
    _remotePath = remotePath;
    _startTime = DateTime.now();

    // Monitor for unexpected exit; no-op if stop() already ran first.
    process.exitCode.then((_) {
      if (isRecording) {
        _log.warning('screenrecord process exited unexpectedly on $deviceId');
        _reset();
      }
    });

    return remotePath;
  }

  Future<String> stop({String? savePath}) async {
    if (!isRecording) throw StateError('stop() called with no active recording');
    final process = _process!;
    final deviceId = _deviceId!;
    final remotePath = _remotePath!;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final localPath = savePath ?? _defaultLocalPath(timestamp);

    // Reset before async work so the exitCode monitor sees isRecording=false.
    _reset();

    process.kill(ProcessSignal.sigint);
    await process.exitCode;

    await Directory(localPath).parent.create(recursive: true);
    await _adb.pullFile(deviceId, remotePath, localPath);
    await _adb.removeFile(deviceId, remotePath);

    return localPath;
  }

  void _reset() {
    _process = null;
    _deviceId = null;
    _remotePath = null;
    _startTime = null;
  }

  String _defaultLocalPath(int timestamp) {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/Downloads/scrcpy_records/rec_$timestamp.mp4';
  }
}
