import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:scrcpy_view_example/safe_adb_client.dart';
import 'package:scrcpy_view_example/stream_stats.dart';

class AppController extends ChangeNotifier {
  AppController._() {
    scrcpyController.addListener(_scheduleNotify);
  }

  static final _instance = AppController._();
  factory AppController() => _instance;

  final List<String> _logs = [];
  late final UnmodifiableListView<String> logs = UnmodifiableListView(_logs);

  final ScrcpyViewController scrcpyController = ScrcpyViewController();
  final adbClient = SafeAdbClient();
  final deviceId = "11081FDD4004DY";

  StreamStats _stats = StreamStats();
  StreamStats get stats => _stats;

  bool get showViewer => scrcpyController.isActive;

  bool _disposed = false;
  bool _needsNotify = false;

  void updateStats(StreamStats s) {
    s.deviceWidth = _stats.deviceWidth;
    s.deviceHeight = _stats.deviceHeight;
    _stats = s;
    _scheduleNotify();
  }

  void addLog(String message) {
    debugPrint('APP_LOG: $message');
    if (_disposed) return;
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _logs.add('$ts: $message');
    if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_needsNotify || _disposed) return;
    _needsNotify = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _needsNotify = false;
      notifyListeners();
    });
  }

  void start() {
    if (scrcpyController.isActive) return;
    addLog('Starting scrcpy viewer...');
    scrcpyController.start(
      adbClient,
      deviceId,
      onStarted: () => addLog('Scrcpy started'),
      onStopped: () => addLog('Scrcpy stopped'),
      onError: (e) => addLog('Error: $e'),
    );
  }

  void stop() {
    if (!scrcpyController.isActive) return;
    addLog('Stopping scrcpy viewer...');
    scrcpyController.stop();
  }

  void injectKey(int keycode) {
    if (_disposed) return;
    addLog('Injecting keycode: $keycode');
    scrcpyController.injectKey(keycode);
  }

  @override
  void dispose() {
    scrcpyController.removeListener(_scheduleNotify);
    scrcpyController.dispose();
    _disposed = true;
    super.dispose();
  }
}
