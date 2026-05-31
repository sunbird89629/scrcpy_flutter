/// Configuration for scrcpy CLI parameters.
class ScrcpyConfig {
  const ScrcpyConfig({
    this.scrcpyPath = 'scrcpy',
    this.maxSize = 1024,
    this.videoBitRate = '8M',
    this.videoCodec = 'h264',
    this.mcpPort = 7070,
  });

  final String scrcpyPath;
  final int maxSize;
  final String videoBitRate;
  final String videoCodec;
  final int mcpPort;

  /// Build CLI argument list for a given device serial.
  List<String> toArgs(String serial) {
    return [
      '--serial', serial,
      '--max-size', '$maxSize',
      '--video-bit-rate', videoBitRate,
      '--video-codec', videoCodec,
    ];
  }

  Map<String, dynamic> toJson() => {
        'scrcpyPath': scrcpyPath,
        'maxSize': maxSize,
        'videoBitRate': videoBitRate,
        'videoCodec': videoCodec,
        'mcpPort': mcpPort,
      };

  factory ScrcpyConfig.fromJson(Map<String, dynamic> json) {
    return ScrcpyConfig(
      scrcpyPath: json['scrcpyPath'] as String? ?? 'scrcpy',
      maxSize: json['maxSize'] as int? ?? 1024,
      videoBitRate: json['videoBitRate'] as String? ?? '8M',
      videoCodec: json['videoCodec'] as String? ?? 'h264',
      mcpPort: json['mcpPort'] as int? ?? 7070,
    );
  }
}
