import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:autoglm_scrcpy/src/scrcpy_packet.dart';

/// A proxy that serves H264 NALUs over a local TCP socket for VLC/media_kit.
class ScrcpyProxyServer {
  ServerSocket? _server;
  StreamSubscription<ScrcpyPacket>? _subscription;
  
  final List<Socket> _clients = [];
  ScrcpyPacket? _configPacket;
  ScrcpyPacket? _lastKeyframe;
  int _port = 0;
  final Completer<void> _readyCompleter = Completer<void>();

  /// The TCP URL that the media player should connect to.
  String get mediaUrl => 'tcp://127.0.0.1:$_port';

  /// Resolves after SPS/PPS + first keyframe have been buffered so a media
  /// client can immediately get a decodable burst on connect.
  Future<void> get ready => _readyCompleter.future;

  /// Starts the proxy server by listening on a local TCP port.
  Future<void> start(Stream<ScrcpyPacket> packets) async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    print('[ScrcpyProxyServer] Media listener ready on $mediaUrl');

    _server!.listen((Socket client) {
      print('[ScrcpyProxyServer] Media client connected: ${client.remoteAddress.address}');
      
      // Send initial burst: SPS/PPS + Latest Keyframe combined
      final builder = BytesBuilder();
      if (_configPacket != null) {
        _appendPacketToBuilder(builder, _configPacket!);
      }
      if (_lastKeyframe != null) {
        _appendPacketToBuilder(builder, _lastKeyframe!);
      }
      
      final burst = builder.takeBytes();
      if (burst.isNotEmpty) {
        print('[ScrcpyProxyServer] Sending initial burst (${burst.length} bytes)');
        client.add(burst);
        client.flush();
      }
      
      _mediaClients_add(client);
      
      unawaited(client.done.then((_) {
        print('[ScrcpyProxyServer] Media client disconnected');
        _mediaClients_remove(client);
      }).catchError((Object e) {
        print('[ScrcpyProxyServer] Media client error: $e');
        _mediaClients_remove(client);
      }));
    });

    _subscription = packets.listen(
      (packet) {
        if (packet.type == ScrcpyPacketType.configuration) {
          _configPacket = packet;
        } else if (packet.isKeyFrame) {
          _lastKeyframe = packet;
        }
        if (!_readyCompleter.isCompleted &&
            _configPacket != null &&
            _lastKeyframe != null) {
          _readyCompleter.complete();
        }

        final builder = BytesBuilder();
        _appendPacketToBuilder(builder, packet);
        final data = builder.takeBytes();

        for (final client in List<Socket>.from(_clients)) {
          try {
            client.add(data);
          } catch (e) {
            client.close();
            _clients.remove(client);
          }
        }
      },
      onDone: stop,
      onError: (Object e) {
        print('[ScrcpyProxyServer] Packet stream error: $e');
        stop();
      },
    );
  }

  void _mediaClients_add(Socket client) => _clients.add(client);
  void _mediaClients_remove(Socket client) => _clients.remove(client);

  void _appendPacketToBuilder(BytesBuilder builder, ScrcpyPacket packet) {
    final data = packet.data;
    if (data.isEmpty) return;

    if (!_hasStartCode(data)) {
      builder.add(const [0x00, 0x00, 0x00, 0x01]);
    }
    builder.add(data);
  }

  bool _hasStartCode(Uint8List data) {
    if (data.length < 3) return false;
    if (data[0] == 0 && data[1] == 0 && data[2] == 1) return true;
    if (data.length < 4) return false;
    if (data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1) return true;
    return false;
  }

  /// Stops the proxy server.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final client in _clients) {
      await client.close();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    _configPacket = null;
    _lastKeyframe = null;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(
        StateError('ScrcpyProxyServer stopped before becoming ready'),
      );
    }
  }
}
