import 'dart:collection';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

class WebViewController extends ChangeNotifier {
  final List<String> _logs = [];
  late final UnmodifiableListView<String> logs = UnmodifiableListView(_logs);

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  ScrcpyServer? _server;
  String? get playerUrl => _server?.playerUrl;

  bool _disposed = false;
  bool _needsNotify = false;

  void addLog(String message) {
    debugPrint(message);
    if (_disposed) return;
    _logs.add(
      '${DateTime.now().toIso8601String().split('T').last.substring(0, 8)}: '
      '$message',
    );
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
    if (_isRunning) return;
    _isRunning = true;
    _logs.clear();
    _notifyNow();

    const adbClient = AdbClient();

    addLog('Searching for devices...');
    final devices = await adbClient.devices();
    if (devices.isEmpty) {
      addLog('Error: No devices found!');
      _isRunning = false;
      _notifyNow();
      return;
    }

    final deviceId = devices.first;
    addLog('Using device: $deviceId');

    final server = ScrcpyServer(
      adbClient: adbClient,
      deviceId: deviceId,
    );

    addLog('Starting scrcpy server...');
    await server.start();

    if (_disposed) {
      await server.stop();
      return;
    }

    _server = server;
    addLog('Web Player URL: ${server.playerUrl}');
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

  void sendTouch(ScrcpyInjectTouchMessage msg) {
    if (_disposed) return;
    _server?.sendControlMessage(msg);
  }

  @override
  void dispose() {
    _disposed = true;
    _server?.stop();
    super.dispose();
  }
}
