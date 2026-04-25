import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart'; // FVPControllerExtensions.setBufferRange
import 'package:video_player/video_player.dart';

/// Owns every piece of mutable state the harness shares between
/// [ScreenView] (the video surface) and [ControlView] (the buttons + log
/// pane). Listeners get notified on log append, run-state flips, and when
/// the [VideoPlayerController] is swapped.
class HarnessController extends ChangeNotifier {
  HarnessController({
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

      // Bypass scrcpy's built-in MPEG-TS proxy and pipe its parsed Annex-B
      // packet stream straight into our raw H.264 proxy.
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
      appLogger.e('[fvp-test] start failed', e, st);
      _isRunning = false;
      notifyListeners();
    }
  }

  void _onControllerTick() {
    _tickCount++;
    if (_tickCount % 30 != 0) return;
    final c = _videoController;
    if (c == null) return;
    final v = c.value;
    if (v.hasError) _log('Player error: ${v.errorDescription}');
    final pos = v.position.inMilliseconds;
    final buffered =
        v.buffered.isNotEmpty ? v.buffered.last.end.inMilliseconds - pos : 0;
    _log('tick: pos=${pos}ms bufferedAhead=${buffered}ms');
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

/// Inherited scope exposing a [HarnessController] to descendants. Any
/// widget that calls [HarnessScope.of] in its `build` rebuilds when the
/// controller calls `notifyListeners()`.
class HarnessScope extends InheritedNotifier<HarnessController> {
  const HarnessScope({
    super.key,
    required HarnessController controller,
    required super.child,
  }) : super(notifier: controller);

  static HarnessController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HarnessScope>();
    assert(scope != null, 'HarnessScope.of() called without an ancestor');
    return scope!.notifier!;
  }
}

/// Serves scrcpy's parsed Annex-B H.264 stream over HTTP, raw, with no
/// container. libmdk's ffmpeg build carries the `h264` demuxer, so the URL
/// suffix `.h264` plus `Content-Type: video/h264` is enough for it to pick
/// the right parser.
///
/// Each new HTTP client gets: cached SPS/PPS + the next keyframe + every
/// frame after. Stale clients just get the live tail.
class RawH264Proxy {
  RawH264Proxy({required void Function(String msg) log}) : _logger = log;

  final void Function(String msg) _logger;

  HttpServer? _server;
  int _port = 0;

  final List<HttpResponse> _pending = [];
  final List<HttpResponse> _active = [];

  Uint8List? _sps;
  Uint8List? _pps;
  Uint8List? _configAnnexB;
  final Completer<void> _readyForClient = Completer<void>();

  String get url => 'http://127.0.0.1:$_port/live.h264';

  /// Resolves once at least one decodable keyframe has been seen — the point
  /// at which it is safe to attach the player.
  Future<void> get readyForClient => _readyForClient.future;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _logger('Raw H.264 proxy listening on $url');

    _server!.listen((req) async {
      if (!req.uri.path.endsWith('.h264')) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      final res = req.response
        ..bufferOutput = false
        ..headers.contentType = ContentType('video', 'h264')
        ..headers.set('Cache-Control', 'no-cache')
        ..headers.set('Connection', 'keep-alive');

      _logger(
        'HTTP client: ${req.connectionInfo?.remoteAddress.address}:'
        '${req.connectionInfo?.remotePort}',
      );

      // New clients buffer in `_pending` until the next IDR — they need the
      // GOP prefix + keyframe to start decoding cleanly.
      _pending.add(res);

      unawaited(
        res.done.then((_) => _drop(res)).catchError((Object e) {
          _logger('client error: $e');
          _drop(res);
        }),
      );
    });
  }

  void feed(ScrcpyPacket packet) {
    if (packet.type == ScrcpyPacketType.configuration) {
      // scrcpy emits SPS+PPS as a single Annex-B blob — cache verbatim and
      // re-prepend it before every keyframe.
      _configAnnexB = _ensureAnnexB(packet.data);
      _splitSpsPps(_configAnnexB!);
      _logger('cached config: ${_configAnnexB!.length} bytes');
      return;
    }

    final frame = _ensureAnnexB(packet.data);

    if (packet.isKeyFrame) {
      final prefix = _configAnnexB;
      final keyBytes = prefix == null
          ? frame
          : (BytesBuilder(copy: false)..add(prefix)..add(frame)).takeBytes();

      if (_pending.isNotEmpty) {
        _logger('IDR keyframe: flushing ${_pending.length} pending client(s)');
        _active.addAll(_pending);
        _pending.clear();
      }
      if (!_readyForClient.isCompleted) _readyForClient.complete();
      _broadcast(keyBytes);
    } else {
      _broadcast(frame);
    }
  }

  void _broadcast(Uint8List bytes) {
    // Reverse iteration so per-client write failures can remove from
    // `_active` in place without copying the list every frame.
    for (var i = _active.length - 1; i >= 0; i--) {
      final c = _active[i];
      try {
        c.add(bytes);
      } on Object catch (e) {
        _logger('write error: $e');
        unawaited(c.close());
        _active.removeAt(i);
      }
    }
  }

  void _drop(HttpResponse c) {
    _active.remove(c);
    _pending.remove(c);
  }

  Future<void> stop() async {
    for (final c in [..._active, ..._pending]) {
      try {
        await c.close();
      } on Object {
        // Ignore per-client shutdown failures — we're tearing down anyway.
      }
    }
    _active.clear();
    _pending.clear();
    await _server?.close(force: true);
    _server = null;
  }

  static bool _hasStartCode(Uint8List d) {
    return (d.length >= 3 && d[0] == 0 && d[1] == 0 && d[2] == 1) ||
        (d.length >= 4 && d[0] == 0 && d[1] == 0 && d[2] == 0 && d[3] == 1);
  }

  static Uint8List _ensureAnnexB(Uint8List data) {
    if (data.isEmpty || _hasStartCode(data)) return data;
    final out = Uint8List(data.length + 4);
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
    out[3] = 1;
    out.setRange(4, out.length, data);
    return out;
  }

  void _splitSpsPps(Uint8List annexB) {
    final nals = _splitNalUnits(annexB);
    for (final n in nals) {
      if (n.isEmpty) continue;
      final nalType = n[0] & 0x1F;
      if (nalType == 7) _sps = n;
      if (nalType == 8) _pps = n;
    }
    _logger('config nals: sps=${_sps?.length ?? 0} pps=${_pps?.length ?? 0}');
  }

  static List<Uint8List> _splitNalUnits(Uint8List bytes) {
    final out = <Uint8List>[];
    var i = 0;
    var nalStart = -1;
    while (i < bytes.length - 3) {
      final isShort = bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1;
      final isLong = bytes[i] == 0 &&
          bytes[i + 1] == 0 &&
          bytes[i + 2] == 0 &&
          bytes[i + 3] == 1;
      if (isShort || isLong) {
        final headerLen = isLong ? 4 : 3;
        if (nalStart >= 0) {
          out.add(Uint8List.sublistView(bytes, nalStart, i));
        }
        i += headerLen;
        nalStart = i;
      } else {
        i++;
      }
    }
    if (nalStart >= 0 && nalStart < bytes.length) {
      out.add(Uint8List.sublistView(bytes, nalStart));
    }
    return out;
  }
}
