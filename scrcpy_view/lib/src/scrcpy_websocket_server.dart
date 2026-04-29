import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_packet.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A proxy that serves scrcpy's Annex-B H.264 packets over WebSocket
/// and provides a static HTTP server for the web player.
class ScrcpyWebsocketServer {
  HttpServer? _server;
  StreamSubscription<ScrcpyPacket>? _subscription;

  final Set<WebSocketChannel> _clients = {};
  ScrcpyPacket? _configPacket;

  int _port = 0;

  final ScrcpyLogger _log;

  ScrcpyWebsocketServer({ScrcpyLogger logger = const NoOpScrcpyLogger()})
    : _log = logger;

  /// The WebSocket URL.
  String get wsUrl => 'ws://127.0.0.1:$_port/ws';

  /// The HTTP URL for the web player.
  String get playerUrl => 'http://127.0.0.1:$_port/index.html?ws=$wsUrl';

  /// Starts the WebSocket and Static HTTP server.
  Future<void> start(
    Stream<ScrcpyPacket> packets, {
    required String staticPath,
  }) async {
    final wsHandler = webSocketHandler((
      WebSocketChannel webSocket,
      String? protocol,
    ) {
      _log.info(
        '[ScrcpyWebsocketServer] New WS client connected (protocol: $protocol)',
      );
      _clients.add(webSocket);

      // Send configuration packet immediately if available
      if (_configPacket != null) {
        final hostNow = DateTime.now().microsecondsSinceEpoch;
        final payload = Uint8List(8 + _configPacket!.data.length);
        final bd = ByteData.view(payload.buffer);
        bd.setUint64(0, hostNow);
        payload.setAll(8, _configPacket!.data);
        webSocket.sink.add(payload);
      }

      webSocket.stream.listen(
        (_) {},
        onDone: () => _clients.remove(webSocket),
        onError: (_) => _clients.remove(webSocket),
      );
    });

    final staticHandler = createStaticHandler(
      staticPath,
      defaultDocument: 'index.html',
    );

    final cascade = Cascade()
        .add((Request request) {
          if (request.url.path == 'ws') return wsHandler(request);
          return Response.notFound('Not WS');
        })
        .add(staticHandler);

    _server = await io.serve(cascade.handler, InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _log.info(
      '[ScrcpyWebsocketServer] Server ready on http://127.0.0.1:$_port',
    );

    _subscription = packets.listen((packet) {
      if (packet.type == ScrcpyPacketType.configuration) {
        _configPacket = packet;
        // Don't return, we still want to broadcast config packets to all clients
        // although they are typically handled in the join logic now.
      }

      var data = packet.data;
      if (packet.isKeyFrame && _configPacket != null) {
        final merged = Uint8List(_configPacket!.data.length + data.length);
        merged.setAll(0, _configPacket!.data);
        merged.setAll(_configPacket!.data.length, data);
        data = merged;
      }

      // Protocol Upgrade: [8 bytes Host Timestamp (us)] + [Raw Data]
      final hostNow = DateTime.now().microsecondsSinceEpoch;
      final payload = Uint8List(8 + data.length);
      final bd = ByteData.view(payload.buffer);
      bd.setUint64(0, hostNow);
      payload.setAll(8, data);

      for (final client in _clients) {
        client.sink.add(payload);
      }
    });
  }

  /// Stops the server.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;

    final clientsCopy = List<WebSocketChannel>.from(_clients);
    for (final client in clientsCopy) {
      unawaited(client.sink.close());
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    _configPacket = null;
  }
}
