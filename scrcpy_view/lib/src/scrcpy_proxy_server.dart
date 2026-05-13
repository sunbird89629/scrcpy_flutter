import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_view/src/mpeg_ts_muxer.dart';

/// A proxy that serves scrcpy's Annex-B H.264 packets as MPEG-TS over HTTP.
///
/// media_kit's libmpv ships a trimmed ffmpeg that lacks the raw `h264`
/// demuxer, so the stream is remuxed to MPEG-TS before being sent to the player.
class ScrcpyProxyServer {
  ScrcpyProxyServer({ScrcpyLogger logger = const NoOpScrcpyLogger()})
      : _log = logger;
  HttpServer? _server;
  StreamSubscription<ScrcpyPacket>? _subscription;

  final List<HttpResponse> _activeClients = [];
  final List<HttpResponse> _pendingClients = [];

  final MpegTsMuxer _muxer = MpegTsMuxer();
  ScrcpyPacket? _configPacket;

  int _port = 0;
  final Completer<void> _readyCompleter = Completer<void>();

  final ScrcpyLogger _log;

  /// The URL for the media player to connect to.
  String get proxyUrl => 'http://127.0.0.1:$_port/live';

  /// Resolves when the proxy has received the configuration packet (SPS/PPS).
  Future<void> get ready => _readyCompleter.future;

  /// Starts the proxy server.
  Future<void> start(Stream<ScrcpyPacket> packets) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _log.info('[ScrcpyProxyServer] HTTP Media server ready on $proxyUrl');

    _server!.listen((HttpRequest request) async {
      if (request.uri.path != '/live') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      _log.info(
        '[ScrcpyProxyServer] New HTTP client: '
        '${request.connectionInfo?.remoteAddress.address}:'
        '${request.connectionInfo?.remotePort}',
      );

      final response = request.response
        ..bufferOutput = false
        ..headers.contentType = ContentType('video', 'mp2t')
        ..headers.set('Connection', 'keep-alive')
        ..headers.set('Cache-Control', 'no-cache');

      _pendingClients.add(response);

      unawaited(
        response.done.then((_) {
          _log.info('[ScrcpyProxyServer] HTTP client disconnected');
          _removeClient(response);
        }).catchError((Object e) {
          _log.warn('[ScrcpyProxyServer] Client error: $e');
          _removeClient(response);
        }),
      );
    });

    _subscription = packets.listen((packet) {
      if (packet.type == ScrcpyPacketType.configuration) {
        _log.info(
          '[ScrcpyProxyServer] Received configuration packet '
          '(${packet.data.length} bytes)',
        );
        _configPacket = packet;
        if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        return;
      }

      final isKey = packet.isKeyFrame;
      final Uint8List tsBytes;

      if (isKey && _configPacket != null) {
        final au = _mergeAnnexB([_configPacket!.data, packet.data]);
        final b = BytesBuilder()
          ..add(_muxer.buildPat())
          ..add(_muxer.buildPmt())
          ..add(_muxer.wrapAccessUnit(au, isKey: true));
        tsBytes = b.takeBytes();

        if (_pendingClients.isNotEmpty) {
          _log.info(
            '[ScrcpyProxyServer] IDR Keyframe: flushing '
            '${_pendingClients.length} pending clients',
          );
          _activeClients.addAll(_pendingClients);
          _pendingClients.clear();
        }
      } else {
        final au = _ensureAnnexB(packet.data);
        tsBytes = _muxer.wrapAccessUnit(au, isKey: false);
      }

      final toRemove = <HttpResponse>[];
      for (final client in _activeClients) {
        try {
          client.add(tsBytes);
        } on Exception catch (e) {
          _log.warn('[ScrcpyProxyServer] Client write error: $e');
          unawaited(client.close());
          toRemove.add(client);
        }
      }
      _activeClients.removeWhere(toRemove.contains);
    });
  }

  void _removeClient(HttpResponse client) {
    _activeClients.remove(client);
    _pendingClients.remove(client);
  }

  Uint8List _ensureAnnexB(Uint8List data) {
    if (data.isEmpty || _hasStartCode(data)) return data;
    final out = Uint8List(data.length + 4);
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
    out[3] = 1;
    out.setRange(4, out.length, data);
    return out;
  }

  Uint8List _mergeAnnexB(List<Uint8List> parts) {
    var total = 0;
    for (final d in parts) {
      total += _hasStartCode(d) ? d.length : d.length + 4;
    }
    final out = Uint8List(total);
    var off = 0;
    for (final d in parts) {
      if (!_hasStartCode(d)) {
        out[off++] = 0;
        out[off++] = 0;
        out[off++] = 0;
        out[off++] = 1;
      }
      out.setRange(off, off + d.length, d);
      off += d.length;
    }
    return out;
  }

  bool _hasStartCode(Uint8List d) {
    return (d.length >= 3 && d[0] == 0 && d[1] == 0 && d[2] == 1) ||
        (d.length >= 4 && d[0] == 0 && d[1] == 0 && d[2] == 0 && d[3] == 1);
  }

  /// Stops the proxy server.
  Future<void> stop() async {
    await _subscription?.cancel();
    for (final client in [..._activeClients, ..._pendingClients]) {
      try {
        await client.close();
      } catch (_) {}
    }
    _activeClients.clear();
    _pendingClients.clear();
    await _server?.close(force: true);
    _server = null;
    _configPacket = null;
  }
}
