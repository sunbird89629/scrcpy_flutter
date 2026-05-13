import 'dart:io';
import 'package:adb_tools/src/adb_binary_manager.dart';
import 'package:test/test.dart';

void main() {
  group('AdbBinaryManager', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('adb_mgr_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('ensureAdb returns system adb if available', () async {
      final mgr = AdbBinaryManager(binDir: tempDir.path);
      final path = await mgr.ensureAdb();
      // Should find 'adb' in PATH on this system.
      expect(path, contains('adb'));
      expect(File(path).existsSync(), isTrue);
    });
  });
}
