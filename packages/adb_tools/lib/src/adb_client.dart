import 'dart:io';
import 'dart:typed_data';

import 'package:adb_tools/src/adb_process_runner.dart';
import 'package:adb_tools/src/device_info.dart';
import 'package:adb_tools/src/exceptions.dart';

/// ADB client.
class AdbClient {
  const AdbClient({
    this.adbPath = 'adb',
    this.runner = const AdbProcessRunnerImpl(),
  });

  final String adbPath;
  final AdbProcessRunner runner;

  List<String> _baseArgs(String? deviceId) =>
      deviceId != null ? ['-s', deviceId] : const [];

  Future<String> getVersion() async {
    final result = await runner.run(adbPath, ['version']);
    return result.stdout.toString().trim();
  }

  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'shell',
      ...arguments,
    ], timeout: timeout);
  }

  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'forward',
      if (noRebind) '--no-rebind',
      local,
      remote,
    ]);
  }

  Future<void> forwardRemove(String local, {String? deviceId}) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'forward',
      '--remove',
      local,
    ]);
  }

  Future<void> reverse(
    String remote,
    String local, {
    String? deviceId,
    bool noRebind = false,
  }) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'reverse',
      if (noRebind) '--no-rebind',
      remote,
      local,
    ]);
  }

  Future<void> reverseRemove(String remote, {String? deviceId}) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'reverse',
      '--remove',
      remote,
    ]);
  }

  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'push',
      localPath,
      remotePath,
    ]);
  }

  Future<String> pair(String ip, int port, String code) async {
    if (code.length != 6 || int.tryParse(code) == null) {
      throw const AdbException('Pairing code must be 6 digits.');
    }
    final address = '$ip:$port';
    final result = await runner.run(adbPath, ['pair', address, code]);
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();
    if (stdout.toLowerCase().contains('successfully paired') ||
        stdout.toLowerCase().contains('success')) {
      return 'Successfully paired to $address';
    }
    final combined = '$stdout $stderr'.toLowerCase();
    if (combined.contains('refused')) {
      throw const AdbException(
        'Connection refused - check if wireless debugging is enabled',
      );
    }
    throw AdbException(
      'Pairing failed: ${stdout.isNotEmpty ? stdout : stderr}',
    );
  }

  Future<String> connect(String ip, int port) async {
    final address = '$ip:$port';
    final result = await runner.run(adbPath, ['connect', address]);
    final output = result.stdout.toString().trim();
    if (output.contains('connected to $address') ||
        output.contains('already connected')) {
      return output;
    }
    throw AdbException('Connect failed: $output');
  }

  Future<List<String>> getDevices() async {
    final result = await runner.run(adbPath, ['devices']);
    final lines = result.stdout.toString().split('\n');
    return lines
        .where((item) => item.contains('\t'))
        .map((item) => item.split('\t').first)
        .toList();
  }

  Future<Uint8List> takeScreenshot(String deviceId) async {
    final result = await Process.run(adbPath, [
      '-s',
      deviceId,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null);
    if (result.exitCode != 0) {
      throw AdbException(
        'screencap failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
    return Uint8List.fromList(result.stdout as List<int>);
  }

  Future<DeviceInfo> getDeviceInfo(String serial) async {
    final results = await Future.wait([
      runner.run(adbPath, ['-s', serial, 'shell', 'getprop']),
      runner.run(adbPath, ['-s', serial, 'shell', 'wm', 'size']),
    ]);
    final props = _parseGetprop(results[0].stdout.toString());
    final sizeOut = results[1].stdout.toString();
    final sizeMatch = RegExp(r'(\d+)x(\d+)').firstMatch(sizeOut);
    final sw = sizeMatch != null ? double.parse(sizeMatch.group(1)!) : 0.0;
    final sh = sizeMatch != null ? double.parse(sizeMatch.group(2)!) : 0.0;
    return DeviceInfo(
      serial: serial,
      status: DeviceStatus.online,
      model: props['ro.product.model'],
      manufacturer: props['ro.product.manufacturer'],
      androidVersion: props['ro.build.version.release'],
      sdkVersion: int.tryParse(props['ro.build.version.sdk'] ?? ''),
      screenWidth: sw,
      screenHeight: sh,
    );
  }

  Future<(double, double)> getDeviceScreenInfo(String serial) async {
    try {
      final result = await runner.run(adbPath, [
        ..._baseArgs(serial),
        'shell',
        'wm',
        'size',
      ]);
      final stdout = result.stdout.toString();
      final [double width, double height] = stdout
          .trim()
          .split(':')
          .last
          .trim()
          .split('x')
          .map<double>(double.parse)
          .toList();
      return (width, height);
    } catch (e) {
      throw AdbException('get screen info error: $e');
    }
  }

  /// Returns user-installed package names (excludes system apps).
  Future<List<String>> listUserPackages(String deviceId) async {
    final result = await runner.run(adbPath, [
      '-s',
      deviceId,
      'shell',
      'pm',
      'list',
      'packages',
      '-3',
    ]);
    return result.stdout
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('package:'))
        .map((l) => l.substring('package:'.length))
        .toList()
      ..sort();
  }

  static Map<String, String> _parseGetprop(String output) {
    final regex = RegExp(r'\[([^\]]+)\]:\s*\[([^\]]*)\]');
    final result = <String, String>{};
    for (final match in regex.allMatches(output)) {
      result[match.group(1)!] = match.group(2)!;
    }
    return result;
  }
}
