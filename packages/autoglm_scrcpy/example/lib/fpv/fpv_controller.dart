import 'dart:async';
import 'dart:collection';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:autoglm_scrcpy_example/fpv/raw_h264_proxy.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart';
import 'package:video_player/video_player.dart';

class FpvController extends ChangeNotifier {
  FpvController({
    required this.aggressive,
    required this.bufferMin,
    required this.bufferMax,
  });

  final bool aggressive;
  final int bufferMin;
  final int bufferMax;

  final List<String> _logs = [];
  late final List<String> logs = UnmodifiableListView(_logs);

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  VideoPlayerController? _videoController;
  VideoPlayerController? get videoController => _videoController;

  ScrcpyServer? _server;
  RawH264Proxy? _proxy;
  StreamSubscription<ScrcpyPacket>? _packetSub;
  StreamSubscription<ScrcpyMetadata>? _metaSub;
  int _tickCount = 0;
  bool _disposed = false;

  void _log(String msg) {
    debugPrint(msg);
    if (_disposed) return;
    _logs.add(
      '${DateTime.now().toIso8601String().split('T').last.substring(0, 12)}: '
      '$msg',
    );
    if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
    notifyListeners();
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _logs.clear();
    notifyListeners();

    try {
      const adbClient = AdbClient();
      _log('Searching for devices...');
      final devices = await adbClient.devices();
      if (devices.isEmpty) {
        _log('ERROR: No devices found.');
        _isRunning = false;
        notifyListeners();
        return;
      }
      final deviceId = devices.first;
      _log('Using device: $deviceId');

      final server = ScrcpyServer(adbClient: adbClient, deviceId: deviceId);
      _server = server;

      _metaSub = server.metadata.listen((m) {
        _log('Metadata: ${m.deviceName} (${m.width}x${m.height})');
      });

      final proxy = RawH264Proxy(log: _log);
      _proxy = proxy;
      await proxy.start();

      _packetSub = server.packets.listen(proxy.feed);

      _log('Starting scrcpy server...');
      await server.start();

      _log('Waiting for config packet (SPS/PPS) + first keyframe...');
      await proxy.readyForClient.timeout(const Duration(seconds: 15));

      final url = Uri.parse(proxy.url);
      _log('Opening fvp stream at $url');

      final controller = VideoPlayerController.networkUrl(url);
      _videoController = controller;
      notifyListeners();

      await controller.initialize();
      _log(
        'Initialized: ${controller.value.size.width.toInt()}x'
        '${controller.value.size.height.toInt()}',
      );

      final mediaInfo = controller.getMediaInfo();
      final videoTracks = mediaInfo?.video;
      if (videoTracks != null && videoTracks.isNotEmpty) {
        final v = videoTracks.first;
        _log(
          'video codec=${v.codec.codec} '
          'fmt=${v.codec.format} '
          'colorSpace=${v.codec.colorSpace} '
          '${v.codec.width}x${v.codec.height} '
          'fps=${v.codec.frameRate}',
        );
      }

      controller.setBufferRange(min: bufferMin, max: bufferMax, drop: true);

      await controller.setVolume(0);
      await controller.play();
      _log(
        'Playback started. Buffer=[$bufferMin,$bufferMax]ms, drop=true, '
        'aggressive=$aggressive',
      );

      controller.addListener(_onControllerTick);
    } on Object catch (e, st) {
      _log('ERROR: $e');
      appLogger.e('[fpv] start failed', e, st);
      _isRunning = false;
      notifyListeners();
    }
  }

  void _onControllerTick() {
    _tickCount++;
    if (_tickCount % 10 != 0) return;
    final c = _videoController;
    if (c == null) return;
    final v = c.value;
    if (v.hasError) _log('Player error: ${v.errorDescription}');
    final pos = v.position.inMilliseconds;
    final buffered =
        v.buffered.isNotEmpty ? v.buffered.last.end.inMilliseconds - pos : 0;

    if (buffered > 100 && aggressive) {
      _log('Catching up: ${buffered}ms behind...');
      c.seekTo(v.buffered.last.end);
    } else {
      _log('tick: pos=${pos}ms bufferedAhead=${buffered}ms');
    }
  }

  Future<void> stop() async {
    _videoController?.removeListener(_onControllerTick);
    await _videoController?.dispose();
    _videoController = null;

    await _packetSub?.cancel();
    _packetSub = null;

    await _metaSub?.cancel();
    _metaSub = null;

    await _server?.stop();
    _server = null;

    await _proxy?.stop();
    _proxy = null;

    _log('Stopped.');
    _isRunning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _videoController?.removeListener(_onControllerTick);
    _videoController?.dispose();
    _packetSub?.cancel();
    _metaSub?.cancel();
    _server?.stop();
    _proxy?.stop();
    super.dispose();
  }
}
