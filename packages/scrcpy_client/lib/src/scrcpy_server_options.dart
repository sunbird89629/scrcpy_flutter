import 'package:meta/meta.dart';

/// Configuration options for the scrcpy server.
@immutable
class ScrcpyServerOptions {
  /// Creates a new [ScrcpyServerOptions] instance.
  ///
  /// All parameters are optional and have sensible defaults:
  /// - [maxSize]: 1024 (max display dimension)
  /// - [maxFps]: 60 (frames per second)
  /// - [videoBitRate]: 6000000 (bits per second)
  /// - [videoCodec]: 'h264' (video codec)
  const ScrcpyServerOptions({
    this.maxSize = 1024,
    this.maxFps = 60,
    this.videoBitRate = 6000000,
    this.videoCodec = 'h264',
  });

  /// Maximum display dimension (shorter edge will be scaled to this).
  final int maxSize;

  /// Maximum frames per second.
  final int maxFps;

  /// Video bit rate in bits per second.
  final int videoBitRate;

  /// Video codec (e.g., 'h264', 'h265').
  final String videoCodec;
}
