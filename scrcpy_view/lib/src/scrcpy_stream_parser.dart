import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_packet.dart';

/// Metadata about the scrcpy video stream.
class ScrcpyMetadata {
  const ScrcpyMetadata({
    required this.deviceName,
    required this.width,
    required this.height,
  });

  final String deviceName;
  final int width;
  final int height;
}

/// Parser for scrcpy binary stream.
class ScrcpyStreamParser {
  ScrcpyStreamParser({this.logger = const NoOpScrcpyLogger()});

  final ScrcpyLogger logger;

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

  /// The most recently parsed metadata, or `null` if not seen yet.
  ScrcpyMetadata? get currentMetadata => _currentMetadata;

  /// Feed raw bytes into the parser.
  void feed(Uint8List data) {
    _buffer.addAll(data);
    _process();
  }

  void _process() {
    if (!_headerParsed) {
      const headerSize = 64 + 12; // name + codec + resolution
      if (_buffer.length < headerSize) {
        logger.debug(
          '[ScrcpyStreamParser] Waiting for metadata header: '
          '${_buffer.length}/$headerSize bytes',
        );
        return;
      }

      final nameBytes = Uint8List.fromList(_buffer.sublist(0, 64));
      final deviceName = const Utf8Decoder(allowMalformed: true)
          .convert(nameBytes.takeWhile((c) => c != 0).toList());

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
      logger.info(
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

      const ptsConfig = 0x8000000000000000;
      const ptsKeyframe = 0x4000000000000000;

      if ((ptsRaw & ptsConfig) != 0) {
        logger.info(
          '[ScrcpyStreamParser] CONFIG packet (SPS/PPS): $length bytes'
          ' (ptsRaw: 0x${ptsRaw.toRadixString(16)})',
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
          logger.info(
            '[ScrcpyStreamParser] KEYFRAME packet: $length bytes, pts=$pts'
            ' (ptsRaw: 0x${ptsRaw.toRadixString(16)})',
          );
        } else if (_videoPacketLogCountdown > 0) {
          logger.debug(
            '[ScrcpyStreamParser] video packet: $length bytes, pts=$pts'
            ' (ptsRaw: 0x${ptsRaw.toRadixString(16)})',
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
