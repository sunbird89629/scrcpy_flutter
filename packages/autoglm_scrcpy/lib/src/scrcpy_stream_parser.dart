import 'dart:async';
import 'dart:typed_data';

import 'package:autoglm_scrcpy/src/scrcpy_packet.dart';

/// Metadata about the scrcpy video stream.
class ScrcpyMetadata {
  /// Creates a new [ScrcpyMetadata].
  const ScrcpyMetadata({
    required this.deviceName,
    required this.width,
    required this.height,
  });

  /// The device name.
  final String deviceName;

  /// Video width.
  final int width;

  /// Video height.
  final int height;
}

/// Parser for scrcpy binary stream.
class ScrcpyStreamParser {
  /// Creates a new [ScrcpyStreamParser].
  ScrcpyStreamParser();

  final _buffer = <int>[];
  final _controller = StreamController<ScrcpyPacket>();
  final _metadataController = StreamController<ScrcpyMetadata>.broadcast();

  bool _headerParsed = false;

  /// Stream of parsed scrcpy packets.
  Stream<ScrcpyPacket> get packets => _controller.stream;

  /// Stream of scrcpy metadata (emitted once at start).
  Stream<ScrcpyMetadata> get metadata => _metadataController.stream;

  /// Feed raw bytes into the parser.
  void feed(Uint8List data) {
    _buffer.addAll(data);
    _process();
  }

  void _process() {
    if (!_headerParsed) {
      // Scrcpy v3 protocol:
      // 1 byte dummy (usually handled by scrcpy-server or skipped)
      // 64 bytes device name
      // 4 bytes codec id + 4 bytes width + 4 bytes height (if send_codec_meta)
      // For simplicity, we assume default scrcpy options used in AutoGLM-GUI.

      const headerSize = 64 + 12; // name + codec + resolution
      print('[ScrcpyStreamParser] Buffer length: ${_buffer.length}, needed: $headerSize');
      if (_buffer.length < headerSize) return;

      final nameBytes = Uint8List.fromList(_buffer.sublist(0, 64));
      final deviceName =
          String.fromCharCodes(nameBytes.takeWhile((c) => c != 0));

      final bd = ByteData.sublistView(
        Uint8List.fromList(_buffer.sublist(64, headerSize)),
      );
      // codec = bd.getUint32(0);
      final width = bd.getUint32(4);
      final height = bd.getUint32(8);

      final metadataObj = ScrcpyMetadata(
        deviceName: deviceName,
        width: width,
        height: height,
      );
      print('[ScrcpyStreamParser] Parsed metadata: $deviceName ${width}x$height');
      _metadataController.add(metadataObj);

      _buffer.removeRange(0, headerSize);
      _headerParsed = true;
    }

    // Process packets: 8 bytes PTS + 4 bytes Length + payload
    while (_buffer.length >= 12) {
      final bd = ByteData.sublistView(
        Uint8List.fromList(_buffer.sublist(0, 12)),
      );
      final ptsRaw = bd.getUint64(0);
      final length = bd.getUint32(8);

      if (_buffer.length < 12 + length) break;

      final payload = Uint8List.fromList(_buffer.sublist(12, 12 + length));
      _buffer.removeRange(0, 12 + length);

      // Bits 63 and 62 of PTS are special:
      // Bit 63 (1 << 63): CONFIG (SPS/PPS)
      // Bit 62 (1 << 62): KEYFRAME
      const ptsConfig = 1 << 63;
      const ptsKeyframe = 1 << 62;

      if ((ptsRaw & ptsConfig) != 0) {
        _controller.add(
          ScrcpyPacket(
            type: ScrcpyPacketType.configuration,
            data: payload,
          ),
        );
      } else {
        final isKey = (ptsRaw & ptsKeyframe) != 0;
        final pts = ptsRaw & ~ptsKeyframe;
        _controller.add(
          ScrcpyPacket(
            type: ScrcpyPacketType.video,
            data: payload,
            pts: pts,
            isKeyFrame: isKey,
          ),
        );
      }
    }
  }

  /// Close the parser.
  void close() {
    _controller.close();
    _metadataController.close();
  }
}
