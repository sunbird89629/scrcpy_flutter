import 'dart:async';
import 'dart:io';

import 'package:logger_utils/logger_utils.dart';
import 'package:test/test.dart';
import 'package:scrcpy_mcp/src/recording_adb.dart';
import 'package:scrcpy_mcp/src/recording_controller.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockRecordingAdb implements RecordingAdb {
  final List<(String, String)> startCalls = [];
  final List<(String, String, String)> pullCalls = [];
  final List<(String, String)> removeCalls = [];

  _FakeProcess? _lastProcess;
  Exception? pullError;

  void simulateUnexpectedExit(int code) =>
      _lastProcess!._completer.complete(code);

  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) async {
    startCalls.add((deviceId, remotePath));
    _lastProcess = _FakeProcess();
    return _lastProcess!;
  }

  @override
  Future<void> pullFile(
    String deviceId,
    String remotePath,
    String localPath,
  ) async {
    pullCalls.add((deviceId, remotePath, localPath));
    final err = pullError;
    if (err != null) throw err;
  }

  @override
  Future<void> removeFile(String deviceId, String remotePath) async {
    removeCalls.add((deviceId, remotePath));
  }
}

class _FakeProcess implements RecordingProcess {
  final _completer = Completer<int>();
  bool _killed = false;

  bool get wasKilled => _killed;

  @override
  Future<int> get exitCode => _completer.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_killed) {
      _killed = true;
      if (!_completer.isCompleted) _completer.complete(0);
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RecordingController', () {
    late _MockRecordingAdb adb;
    late RecordingController ctrl;
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('recording_test');
      initLogging(logsDir: tempDir.path);
      adb = _MockRecordingAdb();
      ctrl = RecordingController(adb);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // ── Initial state ──────────────────────────────────────────────────────

    test('isRecording is false initially', () {
      expect(ctrl.isRecording, isFalse);
    });

    test('status is idle initially', () {
      final s = ctrl.status;
      expect(s.isRecording, isFalse);
      expect(s.deviceId, isNull);
      expect(s.startTime, isNull);
      expect(s.remotePath, isNull);
    });

    // ── Start ──────────────────────────────────────────────────────────────

    test('start() sets isRecording and returns /sdcard remote path', () async {
      final remotePath = await ctrl.start('emulator-5554');

      expect(ctrl.isRecording, isTrue);
      expect(remotePath, startsWith('/sdcard/mcp_rec_'));
      expect(remotePath, endsWith('.mp4'));
    });

    test('start() passes device_id to adb', () async {
      await ctrl.start('emulator-5554');

      expect(adb.startCalls, hasLength(1));
      expect(adb.startCalls.first.$1, 'emulator-5554');
    });

    test('status reflects running recording', () async {
      await ctrl.start('emulator-5554');
      final s = ctrl.status;

      expect(s.isRecording, isTrue);
      expect(s.deviceId, 'emulator-5554');
      expect(s.startTime, isNotNull);
      expect(s.remotePath, startsWith('/sdcard/mcp_rec_'));
    });

    // ── Stop ───────────────────────────────────────────────────────────────

    test('stop() sends SIGINT and sets isRecording to false', () async {
      await ctrl.start('emulator-5554');
      await ctrl.stop(savePath: '/tmp/rec_test.mp4');

      expect(ctrl.isRecording, isFalse);
      expect(adb._lastProcess!.wasKilled, isTrue);
    });

    test('stop() calls pullFile then removeFile with matching paths', () async {
      await ctrl.start('emulator-5554');
      await ctrl.stop(savePath: '/tmp/rec_test.mp4');

      expect(adb.pullCalls, hasLength(1));
      expect(adb.removeCalls, hasLength(1));
      expect(adb.pullCalls.first.$2, adb.removeCalls.first.$2);
    });

    test('stop() returns the requested local path', () async {
      await ctrl.start('emulator-5554');
      final localPath = await ctrl.stop(savePath: '/tmp/rec_out.mp4');

      expect(localPath, '/tmp/rec_out.mp4');
    });

    test('stop() uses default ~/Downloads path when savePath is null',
        () async {
      await ctrl.start('emulator-5554');
      final localPath = await ctrl.stop();

      expect(localPath, contains('Downloads/scrcpy_records/rec_'));
      expect(localPath, endsWith('.mp4'));
    });

    // ── Error cases ────────────────────────────────────────────────────────

    test('start() while recording throws StateError', () async {
      await ctrl.start('emulator-5554');

      await expectLater(() => ctrl.start('emulator-5554'), throwsStateError);
    });

    test('pullFile failure rethrows and does NOT call removeFile', () async {
      adb.pullError = Exception('adb pull failed');
      await ctrl.start('emulator-5554');

      await expectLater(
        () => ctrl.stop(savePath: '/tmp/rec_test.mp4'),
        throwsException,
      );
      expect(adb.removeCalls, isEmpty);
    });

    // ── Unexpected exit ────────────────────────────────────────────────────

    test('unexpected process exit resets state to idle', () async {
      await ctrl.start('emulator-5554');
      expect(ctrl.isRecording, isTrue);

      adb.simulateUnexpectedExit(1);
      await Future<void>.delayed(Duration.zero); // let then() callback run

      expect(ctrl.isRecording, isFalse);
    });

    // ── Status JSON ────────────────────────────────────────────────────────

    test('status.toJson() when idle omits optional keys', () {
      final json = ctrl.status.toJson();

      expect(json['is_recording'], isFalse);
      expect(json.containsKey('device_id'), isFalse);
      expect(json.containsKey('start_time'), isFalse);
      expect(json.containsKey('remote_path'), isFalse);
    });

    test('status.toJson() while recording includes all keys', () async {
      await ctrl.start('emulator-5554');
      final json = ctrl.status.toJson();

      expect(json['is_recording'], isTrue);
      expect(json['device_id'], 'emulator-5554');
      expect(json.containsKey('start_time'), isTrue);
      expect(json.containsKey('remote_path'), isTrue);
    });
  });
}
