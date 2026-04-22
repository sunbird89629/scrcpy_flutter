import 'dart:io';

import 'package:archive/archive.dart';
import 'package:autoglm_adb/src/exceptions.dart';
import 'package:autoglm_core/autoglm_core.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

/// Manages the ADB binary lifecycle, including auto-downloading.
class AdbBinaryManager {
  /// Creates a new [AdbBinaryManager].
  AdbBinaryManager({
    required this.binDir,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  /// The directory where the adb binary is (or will be) stored.
  final String binDir;
  final Dio _dio;

  /// Returns the path to a usable ADB binary.
  /// Checks system PATH first, then [binDir].
  /// Downloads from Google if not found.
  Future<String> ensureAdb() async {
    // 1. Check system PATH
    final systemAdb = _which('adb');
    if (systemAdb != null) {
      return systemAdb;
    }

    final adbName = Platform.isWindows ? 'adb.exe' : 'adb';
    final cachedAdb = p.join(binDir, adbName);

    // 2. Check cached binary
    if (File(cachedAdb).existsSync()) {
      await _ensureExecutable(cachedAdb);
      return cachedAdb;
    }

    // 3. Download from Google
    await _downloadPlatformTools();

    if (File(cachedAdb).existsSync()) {
      await _ensureExecutable(cachedAdb);
      return cachedAdb;
    }

    throw const AdbException('Failed to find or download ADB binary.');
  }

  String? _which(String command) {
    try {
      final res = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        [command],
      );
      if (res.exitCode == 0) {
        return res.stdout.toString().trim().split('\n').first;
      }
    } on Exception catch (e, st) {
      AppLogger.maybeError('Error in _which for $command', e, st);
    }
    return null;
  }

  Future<void> _ensureExecutable(String path) async {
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', path]);
    }
  }

  Future<void> _downloadPlatformTools() async {
    final platform = _getPlatformName();
    final url =
        'https://dl.google.com/android/repository/platform-tools-latest-$platform.zip';
    final zipPath = p.join(binDir, 'platform-tools.zip');

    final dir = Directory(binDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    await _dio.download(url, zipPath);

    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        // Strip the leading "platform-tools/" prefix
        final parts = p.split(filename);
        if (parts.length < 2) continue;

        final relPath = p.joinAll(parts.sublist(1));
        final data = file.content as List<int>;
        final outFile = File(p.join(binDir, relPath));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
      }
    }

    await File(zipPath).delete();
  }

  String _getPlatformName() {
    if (Platform.isMacOS) return 'darwin';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
