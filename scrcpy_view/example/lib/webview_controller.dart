import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrcpy_adapters/scrcpy_adapters.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class StreamStats {
  String status;
  int latencyMs;
  int fps;
  int buffered;
  int width;
  int height;
  int cssWidth;
  int cssHeight;
  int deviceWidth;
  int deviceHeight;

  StreamStats({
    this.status = 'Connecting...',
    this.latencyMs = 0,
    this.fps = 0,
    this.buffered = 0,
    this.width = 0,
    this.height = 0,
    this.cssWidth = 0,
    this.cssHeight = 0,
    this.deviceWidth = 0,
    this.deviceHeight = 0,
  });

  factory StreamStats.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return StreamStats(
      status: map['status'] as String? ?? '',
      latencyMs: (map['latencyMs'] as num?)?.toInt() ?? 0,
      fps: (map['fps'] as num?)?.toInt() ?? 0,
      buffered: (map['buffered'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      cssWidth: (map['cssWidth'] as num?)?.toInt() ?? 0,
      cssHeight: (map['cssHeight'] as num?)?.toInt() ?? 0,
    );
  }

  String get resolution => width > 0 && height > 0 ? '${width}x$height' : 'N/A';
  String get cssResolution =>
      cssWidth > 0 && cssHeight > 0 ? '${cssWidth}x$cssHeight' : 'N/A';
  String get deviceResolution => deviceWidth > 0 && deviceHeight > 0
      ? '${deviceWidth}x$deviceHeight'
      : 'N/A';
}

class WebViewController extends ChangeNotifier {
  WebViewController._();
  static final _instance = WebViewController._();
  factory WebViewController() => _instance;

  final List<String> _logs = [];
  late final UnmodifiableListView<String> logs = UnmodifiableListView(_logs);

  bool _isRunning = false;
  bool get isRunning => _isRunning;
  final adbClient = AdbClientAdapter.withPath();
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
  String? get playerUrl => _server?.playerUrl;

  bool _disposed = false;
  bool _needsNotify = false;

  void addLog(String message) {
    debugPrint(message);
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
    if (_isRunning) return;
    _isRunning = true;
    _logs.clear();
    _notifyNow();

    addLog('Searching for devices...');

    try {
      final result = await adbClient.shell(['wm', 'size'], deviceId: deviceId);
      final out = result.stdout.toString().trim();
      final match = RegExp(r'(\d+)x(\d+)').firstMatch(out);
      if (match != null) {
        _stats.deviceWidth = int.parse(match.group(1)!);
        _stats.deviceHeight = int.parse(match.group(2)!);
        addLog('Device resolution: ${_stats.deviceResolution}');
      }
    } catch (e) {
      addLog('Failed to get device resolution: $e');
    }

    final server = ScrcpyServer(
      adb: adbClient,
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
