import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_launcher.dart';

void main() {
  group('ScrcpyLauncher', () {
    test('isRunning tracks process state', () {
      final launcher = ScrcpyLauncher();
      expect(launcher.isRunning, false);
    });

    test('config getter returns current config', () {
      const config = ScrcpyConfig(maxSize: 1280);
      final launcher = ScrcpyLauncher(config: config);
      expect(launcher.config.maxSize, 1280);
    });
  });
}
