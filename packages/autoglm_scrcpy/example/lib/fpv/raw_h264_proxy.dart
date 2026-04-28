import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';

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

      if (_configAnnexB != null) {
        res.add(_configAnnexB!);
      }
      _active.add(res);

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
          : (BytesBuilder(copy: false)
                ..add(prefix)
                ..add(frame))
              .takeBytes();

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
      } on Object {}
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
