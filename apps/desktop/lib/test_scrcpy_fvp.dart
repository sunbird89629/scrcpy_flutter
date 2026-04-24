/// Parallel scrcpy preview harness that swaps the `media_kit` + MPEG-TS
/// pipeline for `fvp` (libmdk) consuming raw H.264 Annex-B directly.
///
/// Run:
///   flutter run -d macos -t lib/test_scrcpy_fvp.dart
///
/// The existing `test_scrcpy.dart` (media_kit path) is untouched — launch it
/// the same way with `-t lib/test_scrcpy.dart` for an A/B comparison.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  fvp.registerWith(
    options: {
      'video.decoders': _preferredDecoders(),
      'lowLatency': 1,
    },
  );

  final tempDir = await getTemporaryDirectory();
  initAppLogger(logsDir: p.join(tempDir.path, 'autoglm_logs'));

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FvpScrcpyTestScreen(),
    ),
  );
}

List<String> _preferredDecoders() {
  if (Platform.isMacOS || Platform.isIOS) {
    return ['VT', 'FFmpeg'];
  }
  if (Platform.isWindows) {
    return ['MFT:d3d=11', 'D3D11', 'DXVA', 'CUDA', 'FFmpeg'];
  }
  if (Platform.isLinux) {
    return ['VAAPI', 'VDPAU', 'CUDA', 'FFmpeg'];
  }
  return ['FFmpeg'];
}

/// Root widget for the fvp-based scrcpy preview harness.
class FvpScrcpyTestScreen extends StatefulWidget {
  /// Creates the harness.
  const FvpScrcpyTestScreen({super.key});

  @override
  State<FvpScrcpyTestScreen> createState() => _FvpScrcpyTestScreenState();
}

class _FvpScrcpyTestScreenState extends State<FvpScrcpyTestScreen> {
  final List<String> _logs = [];
  ScrcpyServer? _server;
  _RawH264Proxy? _proxy;
  StreamSubscription<ScrcpyPacket>? _packetSub;
  VideoPlayerController? _controller;
  bool _isRunning = false;

  void _log(String msg) {
    debugPrint(msg);
    if (!mounted) return;
    setState(() {
      _logs.add(
        '${DateTime.now().toIso8601String().split('T').last.substring(0, 12)}: '
        '$msg',
      );
      if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
    });
  }

  Future<void> _startTest() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _logs.clear();
    });

    try {
      const adbClient = AdbClient();
      _log('Searching for devices...');
      final devices = await adbClient.devices();
      if (devices.isEmpty) {
        _log('ERROR: No devices found.');
        setState(() => _isRunning = false);
        return;
      }
      final deviceId = devices.first;
      _log('Using device: $deviceId');

      final server = ScrcpyServer(adbClient: adbClient, deviceId: deviceId);
      _server = server;

      server.metadata.listen((m) {
        _log('Metadata: ${m.deviceName} (${m.width}x${m.height})');
      });

      // Raw H.264 HTTP proxy (no MPEG-TS muxing).
      final proxy = _RawH264Proxy(logger: _log);
      _proxy = proxy;
      await proxy.start();

      // Fan the scrcpy packet broadcast into the raw proxy. We ignore the
      // server's internal MPEG-TS proxy URL entirely.
      _packetSub = server.packets.listen(proxy.feed);

      _log('Starting scrcpy server...');
      await server.start();

      _log('Waiting for config packet (SPS/PPS) + first keyframe...');
      await proxy.readyForClient.timeout(const Duration(seconds: 15));

      final url = Uri.parse(proxy.url);
      _log('Opening fvp stream at $url');

      final controller = VideoPlayerController.networkUrl(url);
      _controller = controller;

      await controller.initialize();
      _log(
        'Initialized: ${controller.value.size.width.toInt()}x'
        '${controller.value.size.height.toInt()}',
      );

      // The key low-latency knob: drop frames older than 200ms. Min buffer
      // of 0 means render as soon as a frame is decoded.
      controller.setBufferRange(min: 0, max: 200, drop: true);

      await controller.setVolume(0);
      await controller.play();
      _log('Playback started. Buffer range = [0, 200] ms, drop = true');

      controller.addListener(_onControllerTick);
    } on Object catch (e, st) {
      _log('ERROR: $e');
      appLogger.e('[fvp-test] startTest failed', e, st);
    }
  }

  int _tickCount = 0;
  void _onControllerTick() {
    _tickCount++;
    // Log roughly once a second.
    if (_tickCount % 30 != 0) return;
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (v.hasError) {
      _log('Player error: ${v.errorDescription}');
    }
    // Report how deep behind "now" the decoded frontier is.
    final pos = v.position.inMilliseconds;
    final buffered = v.buffered.isNotEmpty
        ? v.buffered.last.end.inMilliseconds - pos
        : 0;
    _log('tick: pos=${pos}ms bufferedAhead=${buffered}ms');
  }

  Future<void> _stopTest() async {
    _controller?.removeListener(_onControllerTick);
    await _controller?.dispose();
    _controller = null;

    await _packetSub?.cancel();
    _packetSub = null;

    await _server?.stop();
    _server = null;

    await _proxy?.stop();
    _proxy = null;

    _log('Stopped.');
    setState(() => _isRunning = false);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerTick);
    _controller?.dispose();
    _packetSub?.cancel();
    _server?.stop();
    _proxy?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('AutoGLM Scrcpy Preview (fvp / libmdk)'),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          SizedBox(
            width: 380,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.indigo[800],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRunning ? null : _startTest,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isRunning ? _stopTest : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Colors.black,
                    padding: const EdgeInsets.all(8),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, i) => Text(
                        _logs[i],
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black,
                border:
                    Border(left: BorderSide(color: Colors.white10, width: 2)),
              ),
              child: Center(
                child: _controller == null || !_controller!.value.isInitialized
                    ? const Text(
                        'No stream. Press Start.',
                        style: TextStyle(color: Colors.white54),
                      )
                    : AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Serves scrcpy's parsed Annex-B H.264 stream over HTTP, raw, with no
/// container. libmdk's ffmpeg build carries the `h264` demuxer, so the URL
/// suffix `.h264` plus `Content-Type: video/h264` is enough for it to pick
/// the right parser.
///
/// Each new HTTP client gets: cached SPS/PPS + the next keyframe + every
/// frame after. Stale clients just get the live tail.
class _RawH264Proxy {
  _RawH264Proxy({required this.logger});

  final void Function(String msg) logger;

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
    logger('Raw H.264 proxy listening on $url');

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

      logger(
        'HTTP client: ${req.connectionInfo?.remoteAddress.address}:'
        '${req.connectionInfo?.remotePort}',
      );

      // New client must wait for the next keyframe so it has a full GOP
      // prefix + IDR. In the interim we buffer it in `_pending`.
      _pending.add(res);

      unawaited(
        res.done.then((_) => _drop(res)).catchError((Object e) {
          logger('client error: $e');
          _drop(res);
        }),
      );
    });
  }

  void feed(ScrcpyPacket packet) {
    if (packet.type == ScrcpyPacketType.configuration) {
      // scrcpy emits a single configuration packet containing both SPS and
      // PPS as a single Annex-B blob. Cache verbatim.
      _configAnnexB = _ensureAnnexB(packet.data);
      _splitSpsPps(_configAnnexB!);
      logger('cached config: ${_configAnnexB!.length} bytes');
      return;
    }

    final frame = _ensureAnnexB(packet.data);

    if (packet.isKeyFrame) {
      final prefix = _configAnnexB;
      final keyBytes = prefix != null ? _concat([prefix, frame]) : frame;

      if (_pending.isNotEmpty) {
        logger('IDR keyframe: flushing ${_pending.length} pending client(s)');
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
    for (final c in List<HttpResponse>.from(_active)) {
      try {
        c.add(bytes);
      } on Object catch (e) {
        logger('write error: $e');
        unawaited(c.close());
        _active.remove(c);
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

  static Uint8List _concat(List<Uint8List> parts) {
    final total = parts.fold<int>(0, (s, p) => s + p.length);
    final out = Uint8List(total);
    var off = 0;
    for (final p in parts) {
      out.setRange(off, off + p.length, p);
      off += p.length;
    }
    return out;
  }

  // Informational only — surfaces whether SPS and PPS both arrived in the
  // configuration packet, which is useful when diagnosing decoder refusals.
  void _splitSpsPps(Uint8List annexB) {
    final nals = _splitNalUnits(annexB);
    for (final n in nals) {
      if (n.isEmpty) continue;
      final nalType = n[0] & 0x1F;
      if (nalType == 7) _sps = n;
      if (nalType == 8) _pps = n;
    }
    logger('config nals: sps=${_sps?.length ?? 0} pps=${_pps?.length ?? 0}');
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
