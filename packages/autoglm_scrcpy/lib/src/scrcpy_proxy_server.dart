import 'dart:async';
import 'dart:io';

import 'package:autoglm_scrcpy/src/scrcpy_packet.dart';

/// A local TCP server that proxies pure H264 NALUs to a media player.
class ScrcpyProxyServer {
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  StreamSubscription<ScrcpyPacket>? _subscription;

  /// The local port the proxy is listening on.
  int get port => _serverSocket?.port ?? 0;

  /// Starts the proxy server and binds to a random available port.
  Future<void> start(Stream<ScrcpyPacket> packets) async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

    _serverSocket!.listen((socket) {
      // Only accept one client (the media player) at a time
      _clientSocket?.destroy();
      _clientSocket = socket;

      _subscription?.cancel();
      _subscription = packets.listen(
        (packet) {
          try {
            _clientSocket?.add(packet.data);
          } on Exception catch (_) {
            // Ignore write errors (e.g., player disconnected)
          }
        },
        onDone: () => _clientSocket?.destroy(),
        onError: (_) => _clientSocket?.destroy(),
      );
    });
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
