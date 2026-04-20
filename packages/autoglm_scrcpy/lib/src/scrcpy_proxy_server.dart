import 'dart:async';
import 'dart:io';

import 'package:autoglm_scrcpy/src/scrcpy_packet.dart';

/// A local TCP server that proxies pure H264 NALUs to a media player.
class ScrcpyProxyServer {
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  StreamSubscription<ScrcpyPacket>? _subscription;
  final _packetBuffer = <ScrcpyPacket>[];
  bool _configSent = false;

  /// The local port the proxy is listening on.
  int get port => _serverSocket?.port ?? 0;

  /// Starts the proxy server and binds to a random available port.
  Future<void> start(Stream<ScrcpyPacket> packets) async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    print('[ScrcpyProxyServer] Listening on port ${_serverSocket!.port}');

    _serverSocket!.listen((socket) {
      print('[ScrcpyProxyServer] Client connected from ${socket.remoteAddress}');
      // Only accept one client (the media player) at a time
      _clientSocket?.destroy();
      _clientSocket = socket;
      _configSent = false;

      _subscription?.cancel();
      _subscription = packets.listen(
        (packet) {
          try {
            // Ensure config packets (SPS/PPS) are sent first
            if (packet.type == ScrcpyPacketType.configuration) {
              _sendPacket(packet);
              _configSent = true;
            } else if (_configSent || _clientSocket == null) {
              _sendPacket(packet);
            } else {
              // Buffer video packets until config is sent
              _packetBuffer.add(packet);
            }
          } on Exception catch (e) {
            print('[ScrcpyProxyServer] Error sending packet: $e');
          }
        },
        onDone: () {
          print('[ScrcpyProxyServer] Packet stream closed');
          _clientSocket?.destroy();
        },
        onError: (Object e) {
          print('[ScrcpyProxyServer] Packet stream error: $e');
          _clientSocket?.destroy();
        },
      );
    });
  }

  void _sendPacket(ScrcpyPacket packet) {
    // Add H264 NAL unit start code (0x00 0x00 0x00 0x01)
    const nalStartCode = [0x00, 0x00, 0x00, 0x01];
    _clientSocket?.add(nalStartCode);
    _clientSocket?.add(packet.data);
  }

  /// Stops the proxy server.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _clientSocket?.destroy();
    _clientSocket = null;
    await _serverSocket?.close();
    _serverSocket = null;
  }
}
