import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_client/src/control_message.dart';
import 'package:scrcpy_client/src/scrcpy_device_provisioner.dart';
import 'package:scrcpy_client/src/scrcpy_logger.dart';
import 'package:scrcpy_client/src/scrcpy_packet.dart';
import 'package:scrcpy_client/src/scrcpy_server_options.dart';
import 'package:scrcpy_client/src/scrcpy_stream_parser.dart';

/// Manages a scrcpy server instance on a device.
class ScrcpyServer {
  /// The scrcpy server version bundled with this package.
  static const serverVersion = '3.3.4';

  ScrcpyServer({
    required ScrcpyDeviceProvisioner provisioner,
    ScrcpyLogger logger = const NoOpScrcpyLogger(),
    StreamSink<List<int>>? controlSink,
  })  : _provisioner = provisioner,
        _log = logger,
        _controlSink = controlSink,
        _parser = ScrcpyStreamParser(logger: logger);

  final ScrcpyDeviceProvisioner _provisioner;

  String get deviceId => _provisioner.deviceId;

  int get port => _provisioner.port;

  ScrcpyServerOptions get options => _provisioner.options;

  final ScrcpyLogger _log;
  final ScrcpyStreamParser _parser;
  final StreamSink<List<int>>? _controlSink;

  bool _isStarting = false;

  Socket? _videoSocket;
  Socket? _controlSocket;
  StreamSubscription<Uint8List>? _videoSubscription;
  StreamSubscription<Uint8List>? _controlSubscription;

  /// Stream of parsed scrcpy packets (video frames).
  Stream<ScrcpyPacket> get packets => _parser.packets;

  /// Stream of scrcpy metadata (device name, codec info).
  Stream<ScrcpyMetadata> get metadata => _parser.metadata;

  /// Last parsed metadata, or `null` if the header has not arrived yet.
  ScrcpyMetadata? get currentMetadata => _parser.currentMetadata;

  /// Starts the scrcpy server: provisions the device, then connects
  /// video + control sockets.
  Future<void> start() async {
    if (_isStarting) return;
    _isStarting = true;

    try {
      _log.info('[ScrcpyServer] Starting for device: $deviceId');
      await _provisioner.provision();
      await _connectAll();
    } finally {
      _isStarting = false;
    }
  }

  /// Sends a control message to the device.
  void sendControlMessage(ScrcpyControlMessage message) {
    final sink = _controlSink ?? _controlSocket;
    if (sink == null) {
      _log.warn('[ScrcpyServer] Cannot send control message: Not connected');
      return;
    }
    sink.add(message.toBinary());
  }

  Future<void> _connectAll() async {
    _videoSocket = await _connectSocket('Video');

    var isFirstByteHandled = false;
    _videoSubscription = _videoSocket!.listen(
      (data) {
        if (!isFirstByteHandled) {
          isFirstByteHandled = true;
          if (data.isNotEmpty && data[0] == 0) {
            if (data.length > 1) _parser.feed(Uint8List.sublistView(data, 1));
            return;
          }
        }
        _parser.feed(data);
      },
      onDone: () => _log.warn('[ScrcpyServer] Video socket closed'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      _controlSocket = await _connectSocket('Control');
    } catch (_) {
      await _videoSubscription?.cancel();
      _videoSubscription = null;
      await _videoSocket?.close();
      _videoSocket = null;
      rethrow;
    }
    _controlSocket!.setOption(SocketOption.tcpNoDelay, true);
    _controlSubscription = _controlSocket!.listen(
      (data) => _log.debug('[ScrcpyServer] Control data: ${data.length} bytes'),
      onDone: () => _log.warn('[ScrcpyServer] Control socket closed'),
    );

    _log.info('[ScrcpyServer] All sockets connected with SCID 0.');
  }

  Future<Socket> _connectSocket(String name) async {
    const maxAttempts = 30;
    const retryDelay = Duration(milliseconds: 500);
    final connectPort = _provisioner.actualPort;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _log.debug(
          '[ScrcpyServer] [$name] Connecting to localhost:$connectPort'
          ' (attempt $attempt)',
        );
        return await Socket.connect('localhost', connectPort);
      } on Exception catch (e) {
        if (attempt >= maxAttempts) rethrow;
        _log.debug('[ScrcpyServer] [$name] attempt $attempt failed: $e');
        await Future<void>.delayed(retryDelay);
      }
    }
    throw Exception('Failed to connect to $name socket');
  }

  /// Stops the scrcpy server and releases all resources.
  Future<void> stop() async {
    _log.info('[ScrcpyServer] Stopping for device: $deviceId');

    await _videoSubscription?.cancel();
    _videoSubscription = null;
    await _controlSubscription?.cancel();
    _controlSubscription = null;
    await _videoSocket?.close();
    _videoSocket = null;
    await _controlSocket?.close();
    _controlSocket = null;

    await _provisioner.depovision();

    _parser.close();
  }
}
