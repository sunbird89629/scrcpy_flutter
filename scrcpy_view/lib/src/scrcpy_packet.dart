import 'dart:typed_data';

/// Type of scrcpy packet.
enum ScrcpyPacketType {
  /// Configuration packet (SPS/PPS).
  configuration,

  /// Video data packet.
  video,
}

/// Represents a single packet from the scrcpy stream.
class ScrcpyPacket {
  /// Creates a new [ScrcpyPacket].
  const ScrcpyPacket({
    required this.type,
    required this.data,
    this.pts,
    this.isKeyFrame = false,
  });

  /// The type of packet.
  final ScrcpyPacketType type;

  /// The raw binary data.
  final Uint8List data;

  /// Presentation timestamp (PTS).
  final int? pts;

  /// Whether this is a key frame.
  final bool isKeyFrame;
}
