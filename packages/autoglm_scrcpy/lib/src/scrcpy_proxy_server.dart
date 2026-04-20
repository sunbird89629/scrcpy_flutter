import 'dart:async';
import 'dart:io';

import 'package:autoglm_scrcpy/src/scrcpy_packet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// A proxy that writes H264 NALUs to a FIFO for media player consumption.
class ScrcpyProxyServer {
  RandomAccessFile? _fifoFile;
  StreamSubscription<ScrcpyPacket>? _subscription;
  bool _configSent = false;
  late final String _fifoPath;

  /// The FIFO path that the media player should read from.
  String get fifoPath => _fifoPath;

  /// Starts the proxy server by creating a FIFO and writing H264 packets to it.
  Future<void> start(Stream<ScrcpyPacket> packets) async {
    // Create FIFO in temp directory
    final tempDir = await getTemporaryDirectory();
    _fifoPath = p.join(tempDir.path, 'scrcpy_h264.fifo');

    // Remove old FIFO if it exists
    try {
      await File(_fifoPath).delete();
    } catch (_) {}

    // Create FIFO using mkfifo command
    final result = await Process.run('mkfifo', [_fifoPath]);
    if (result.exitCode != 0) {
      throw Exception('Failed to create FIFO: ${result.stderr}');
    }
    print('[ScrcpyProxyServer] Created FIFO at $_fifoPath');

    // Open FIFO for writing (non-blocking)
    _openFifo();

    // Subscribe to packets and write to FIFO
    _subscription = packets.listen(
      (packet) {
        try {
          if (packet.type == ScrcpyPacketType.configuration) {
            _writePacket(packet);
            _configSent = true;
            print('[ScrcpyProxyServer] Sent config packet: ${packet.data.length} bytes');
          } else if (_configSent) {
            _writePacket(packet);
            if (packet.isKeyFrame) {
              print('[ScrcpyProxyServer] Sent keyframe: ${packet.data.length} bytes');
            }
          }
        } on Exception catch (e) {
          print('[ScrcpyProxyServer] Error writing packet: $e');
          _openFifo();
        }
      },
      onDone: () {
        print('[ScrcpyProxyServer] Packet stream closed');
      },
      onError: (Object e) {
        print('[ScrcpyProxyServer] Packet stream error: $e');
      },
    );
  }

  void _openFifo() {
    try {
      _fifoFile?.closeSync();
      final file = File(_fifoPath);
      _fifoFile = file.openSync(mode: FileMode.write);
    } catch (e) {
      print('[ScrcpyProxyServer] Could not open FIFO: $e');
    }
  }

  void _writePacket(ScrcpyPacket packet) {
    if (_fifoFile == null) return;
    try {
      // Add H264 NAL unit start code (0x00 0x00 0x00 0x01)
      const nalStartCode = [0x00, 0x00, 0x00, 0x01];
      _fifoFile!.writeFromSync(nalStartCode);
      _fifoFile!.writeFromSync(packet.data);
    } catch (e) {
      print('[ScrcpyProxyServer] Error writing to FIFO: $e');
      _openFifo();
    }
  }

  /// Stops the proxy server.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _fifoFile?.close();
      _fifoFile = null;
      await File(_fifoPath).delete();
    } catch (_) {}
    print('[ScrcpyProxyServer] Stopped');
  }
}
