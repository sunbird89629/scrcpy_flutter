import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';

void main() {
  group('ScrcpyConfig', () {
    test('default values', () {
      const config = ScrcpyConfig();
      expect(config.scrcpyPath, 'scrcpy');
      expect(config.maxSize, 1024);
      expect(config.videoBitRate, '8M');
      expect(config.videoCodec, 'h264');
    });

    test('toArgs produces correct CLI arguments', () {
      const config = ScrcpyConfig(
        maxSize: 1280,
        videoBitRate: '4M',
        videoCodec: 'h265',
      );
      final args = config.toArgs('ABCD1234');
      expect(args, [
        '--serial', 'ABCD1234',
        '--max-size', '1280',
        '--video-bit-rate', '4M',
        '--video-codec', 'h265',
      ]);
    });

    test('toJson and fromJson round-trip', () {
      const config = ScrcpyConfig(
        scrcpyPath: '/usr/local/bin/scrcpy',
        maxSize: 1280,
        videoBitRate: '4M',
        videoCodec: 'h265',
      );
      final json = config.toJson();
      final restored = ScrcpyConfig.fromJson(json);
      expect(restored.scrcpyPath, config.scrcpyPath);
      expect(restored.maxSize, config.maxSize);
      expect(restored.videoBitRate, config.videoBitRate);
      expect(restored.videoCodec, config.videoCodec);
    });
  });
}
