import 'dart:io';

import 'package:adb_tools/src/adb_process_runner.dart';
import 'package:adb_tools/src/exceptions.dart';
import 'package:adb_tools/src/device_info.dart';

/// Abstract ADB client.
///
/// All methods default to [UnimplementedError] so partial test fakes can
/// extend this class and only override the methods they exercise.
abstract class AdbClient {
  const AdbClient();

  Future<String> getVersion() => throw UnimplementedError();

  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      throw UnimplementedError();

  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) =>
      throw UnimplementedError();

  Future<void> forwardRemove(String local, {String? deviceId}) =>
      throw UnimplementedError();

  Future<void> reverse(
    String remote,
    String local, {
    String? deviceId,
    bool noRebind = false,
  }) =>
      throw UnimplementedError();

  Future<void> reverseRemove(String remote, {String? deviceId}) =>
      throw UnimplementedError();

  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) =>
      throw UnimplementedError();

  Future<String> pair(String ip, int port, String code) =>
      throw UnimplementedError();

  Future<String> connect(String ip, int port) => throw UnimplementedError();

  Future<List<String>> getDevices() => throw UnimplementedError();

  Future<List<DeviceInfo>> getDevicesWithInfo() => throw UnimplementedError();
}

/// Concrete ADB client implementation.
class AdbClientImpl extends AdbClient {
  const AdbClientImpl({
    this.adbPath = 'adb',
    this.runner = const AdbProcessRunnerImpl(),
  });

  final String adbPath;
  final AdbProcessRunner runner;

  List<String> _baseArgs(String? deviceId) =>
      deviceId != null ? ['-s', deviceId] : const [];

  @override
  Future<String> getVersion() async {
    final result = await runner.run(adbPath, ['version']);
    return result.stdout.toString().trim();
  }

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return runner.runRaw(
      adbPath,
      [..._baseArgs(deviceId), 'shell', ...arguments],
      timeout: timeout,
    );
  }

  @override
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

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'forward',
      '--remove',
      local,
    ]);
  }

  @override
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

  @override
  Future<void> reverseRemove(String remote, {String? deviceId}) async {
    await runner.run(adbPath, [
      ..._baseArgs(deviceId),
      'reverse',
      '--remove',
      remote,
    ]);
  }

  @override
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

  @override
  Future<String> pair(String ip, int port, String code) async {
    if (code.length != 6 || int.tryParse(code) == null) {
      throw const AdbException('Pairing code must be 6 digits.');
    }
    final address = '$ip:$port';
    final result = await runner.runRaw(adbPath, ['pair', address, code]);
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

  @override
  Future<String> connect(String ip, int port) async {
    final address = '$ip:$port';
    final result = await runner.runRaw(adbPath, ['connect', address]);
    final output = result.stdout.toString().trim();
    if (output.contains('connected to $address') ||
        output.contains('already connected')) {
      return output;
    }
    throw AdbException('Connect failed: $output');
  }

  @override
  Future<List<String>> getDevices() async {
    final result = await runner.run(adbPath, ['devices']);
    final lines = result.stdout.toString().split('\n');
    return [
      for (var i = 1; i < lines.length; i++)
        if (lines[i].trim().isNotEmpty && lines[i].contains('\t'))
          lines[i].trim().split('\t').first,
    ];
  }

  @override
  Future<List<DeviceInfo>> getDevicesWithInfo() async {
    final result = await runner.run(adbPath, ['devices']);
    final lines = result.stdout.toString().split('\n');

    final entries = <({String serial, DeviceStatus status})>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || !line.contains('\t')) continue;
      final parts = line.split('\t');
      final serial = parts[0].trim();
      final rawStatus = parts[1].trim();
      final status = switch (rawStatus) {
        'device' => DeviceStatus.online,
        'offline' => DeviceStatus.offline,
        _ => DeviceStatus.unauthorized,
      };
      entries.add((serial: serial, status: status));
    }

    return Future.wait(
      entries.map((e) async {
        if (e.status != DeviceStatus.online) {
          return DeviceInfo(serial: e.serial, status: e.status);
        }
        try {
          final propResult = await runner.run(
            adbPath,
            ['-s', e.serial, 'shell', 'getprop'],
          );
          final props = _parseGetprop(propResult.stdout.toString());
          return DeviceInfo(
            serial: e.serial,
            status: e.status,
            model: props['ro.product.model'],
            manufacturer: props['ro.product.manufacturer'],
            androidVersion: props['ro.build.version.release'],
            sdkVersion: int.tryParse(props['ro.build.version.sdk'] ?? ''),
          );
        } catch (_) {
          return DeviceInfo(serial: e.serial, status: e.status);
        }
      }),
    );
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
