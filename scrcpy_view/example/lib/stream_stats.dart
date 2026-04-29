import 'dart:convert';

class StreamStats {
  String status;
  int latencyMs;
  int fps;
  int buffered;
  int width;
  int height;
  int cssWidth;
  int cssHeight;
  int deviceWidth;
  int deviceHeight;

  StreamStats({
    this.status = 'Connecting...',
    this.latencyMs = 0,
    this.fps = 0,
    this.buffered = 0,
    this.width = 0,
    this.height = 0,
    this.cssWidth = 0,
    this.cssHeight = 0,
    this.deviceWidth = 0,
    this.deviceHeight = 0,
  });

  factory StreamStats.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return StreamStats(
      status: map['status'] as String? ?? '',
      latencyMs: (map['latencyMs'] as num?)?.toInt() ?? 0,
      fps: (map['fps'] as num?)?.toInt() ?? 0,
      buffered: (map['buffered'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      cssWidth: (map['cssWidth'] as num?)?.toInt() ?? 0,
      cssHeight: (map['cssHeight'] as num?)?.toInt() ?? 0,
    );
  }

  String get resolution => width > 0 && height > 0 ? '${width}x$height' : 'N/A';
  String get cssResolution =>
      cssWidth > 0 && cssHeight > 0 ? '${cssWidth}x$cssHeight' : 'N/A';
  String get deviceResolution => deviceWidth > 0 && deviceHeight > 0
      ? '${deviceWidth}x$deviceHeight'
      : 'N/A';
}
