import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:scrcpy_view_example/safe_adb_client.dart';
import 'package:scrcpy_view_example/stream_stats.dart';

class AppController extends ChangeNotifier {
  AppController._();
  static final _instance = AppController._();
  factory AppController() => _instance;

  final List<String> _logs = [];
  late final UnmodifiableListView<String> logs = UnmodifiableListView(_logs);

  final ScrcpyViewController scrcpyController = ScrcpyViewController();

  bool _isRunning = false;
  bool get isRunning => _isRunning;
  final adbClient = SafeAdbClient();
  final deviceId = "11081FDD4004DY";

  StreamStats _stats = StreamStats();
  StreamStats get stats => _stats;

  void updateStats(StreamStats s) {
    s.deviceWidth = _stats.deviceWidth;
    s.deviceHeight = _stats.deviceHeight;
    _stats = s;
    _scheduleNotify();
  }

  ScrcpyServer? _server;

  bool _disposed = false;
  bool _needsNotify = false;

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

  void _notifyNow() {
    _needsNotify = false;
    notifyListeners();
  }

  Future<void> start() async {
    scrcpyController.start();
    // if (_isRunning) return;
    // _isRunning = true;
    // _logs.clear();
    // _notifyNow();

    // addLog('Searching for devices (ID: $deviceId)...');

    // final result = await adbClient.shell(['wm', 'size'], deviceId: deviceId);
    // final out = result.stdout.toString().trim();
    // addLog('wm size output: $out');
    // final match = RegExp(r'(\d+)x(\d+)').firstMatch(out);
    // if (match != null) {
    //   _stats.deviceWidth = int.parse(match.group(1)!);
    //   _stats.deviceHeight = int.parse(match.group(2)!);
    //   addLog('Device resolution: ${_stats.deviceResolution}');
    // }

    // try {
    //   final server = ScrcpyServer(
    //     adb: adbClient,
    //     deviceId: deviceId,
    //   );

    //   addLog('Starting scrcpy server...');
    //   await server.start();

    //   if (_disposed) {
    //     await server.stop();
    //     return;
    //   }

    //   _server = server;
    //   addLog('Web Player URL: ${server.playerUrl}');
    // } catch (e, s) {
    //   addLog('CRITICAL ERROR starting server: $e');
    //   debugPrintStack(stackTrace: s);
    //   _isRunning = false;
    // }
    _notifyNow();
  }

  Future<void> stop() async {
    if (_disposed) return;
    addLog('--- Stop Button Clicked ---');
    await _server?.stop();
    addLog('Server cleanup finished.');
    _isRunning = false;
    _server = null;
    _notifyNow();
  }

  void injectKey(int keycode) {
    if (_disposed || _server == null) return;
    addLog('Injecting keycode: $keycode');
    _server!.sendControlMessage(
      ScrcpyInjectKeyMessage(action: ScrcpyAction.down, keycode: keycode),
    );
    _server!.sendControlMessage(
      ScrcpyInjectKeyMessage(action: ScrcpyAction.up, keycode: keycode),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _server?.stop();
    super.dispose();
  }
}
