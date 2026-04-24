import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:autoglm_core/autoglm_core.dart';
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
  final _controller = StreamController<ScrcpyPacket>.broadcast();
  final _metadataController = StreamController<ScrcpyMetadata>.broadcast();

  bool _headerParsed = false;
  int _videoPacketLogCountdown = 3;
  ScrcpyMetadata? _currentMetadata;

  /// Stream of parsed scrcpy packets.
  Stream<ScrcpyPacket> get packets => _controller.stream;

  /// Stream of scrcpy metadata (emitted once at start).
  Stream<ScrcpyMetadata> get metadata => _metadataController.stream;

  /// The most recently parsed metadata, or `null` if not seen yet. Use this to
  /// seed late subscribers that missed the one-shot broadcast event.
  ScrcpyMetadata? get currentMetadata => _currentMetadata;

  /// Feed raw bytes into the parser.
  void feed(Uint8List data) {
    _buffer.addAll(data);
    _process();
  }

  void _process() {
    if (!_headerParsed) {
      // Scrcpy protocol bootstrap metadata:
      // (Dummy byte is already consumed by ScrcpyServer)
      // 64 bytes device name (null-terminated/padded)
      // 4 bytes codec id + 4 bytes width + 4 bytes height

      const headerSize = 64 + 12; // name + codec + resolution
      if (_buffer.length < headerSize) {
        appLogger.d(
          '[ScrcpyStreamParser] Waiting for metadata header: '
          '${_buffer.length}/$headerSize bytes',
        );
        return;
      }

      // Read device name (64 bytes)
      final nameBytes = Uint8List.fromList(_buffer.sublist(0, 64));
      // Use Utf8Decoder with allowMalformed: true to avoid crashes
      final deviceName = const Utf8Decoder(allowMalformed: true)
          .convert(nameBytes.takeWhile((c) => c != 0).toList());

      // Read codec info (12 bytes)
      final bd = ByteData.sublistView(
        Uint8List.fromList(_buffer.sublist(64, headerSize)),
      );
      final codecId = bd.getUint32(0);
      final width = bd.getUint32(4);
      final height = bd.getUint32(8);

      final metadataObj = ScrcpyMetadata(
        deviceName: deviceName,
        width: width,
        height: height,
      );
      appLogger.i(
        '[ScrcpyStreamParser] Parsed metadata: $deviceName '
        '${width}x$height (Codec: 0x${codecId.toRadixString(16)})',
      );
      _currentMetadata = metadataObj;
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
      const ptsConfig = 0x8000000000000000;
      const ptsKeyframe = 0x4000000000000000;

      if ((ptsRaw & ptsConfig) != 0) {
        appLogger.i(
          '[ScrcpyStreamParser] CONFIG packet (SPS/PPS): $length bytes (ptsRaw: 0x${ptsRaw.toRadixString(16)})',
        );
        _controller.add(
          ScrcpyPacket(
            type: ScrcpyPacketType.configuration,
            data: payload,
          ),
        );
      } else {
        final isKey = (ptsRaw & ptsKeyframe) != 0;
        final pts = ptsRaw & ~ptsKeyframe;
        if (isKey) {
          appLogger.i(
            '[ScrcpyStreamParser] KEYFRAME packet: $length bytes, pts=$pts (ptsRaw: 0x${ptsRaw.toRadixString(16)})',
          );
        } else if (_videoPacketLogCountdown > 0) {
          appLogger.d(
            '[ScrcpyStreamParser] video packet: $length bytes, pts=$pts (ptsRaw: 0x${ptsRaw.toRadixString(16)})',
          );
          _videoPacketLogCountdown -= 1;
        }
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
