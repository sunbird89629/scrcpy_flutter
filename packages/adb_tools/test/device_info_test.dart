import 'dart:io';

import 'package:adb_tools/src/adb_client.dart';
import 'package:adb_tools/src/adb_process_runner.dart';
import 'package:adb_tools/src/device_info.dart';
import 'package:adb_tools/src/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake runner: maps "arg0 arg1 ..." → stdout string
// ---------------------------------------------------------------------------

class _MapRunner extends AdbProcessRunner {
  _MapRunner(this._map, {this.throwOn});
  final Map<String, String> _map;
  final String? throwOn; // argument substring that triggers throw

  @override
  Future<ProcessResult> runRaw(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final key = arguments.join(' ');
    if (throwOn != null && key.contains(throwOn!)) {
      throw const AdbException('Command failed');
    }
    return ProcessResult(0, 0, _map[key] ?? '', '');
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final key = arguments.join(' ');
    if (throwOn != null && key.contains(throwOn!)) {
      throw const AdbException('Command failed');
    }
    return ProcessResult(0, 0, _map[key] ?? '', '');
  }
}

const _devicesHeader = 'List of devices attached\n';

const _sampleGetprop = '''
[ro.product.model]: [Pixel 8 Pro]
[ro.product.manufacturer]: [Google]
[ro.build.version.release]: [14]
[ro.build.version.sdk]: [34]
[some.other.prop]: [value]
''';

void main() {
  group('AdbClient.getDevicesWithInfo', () {
    test('returns online device with model info', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({
          'devices': '${_devicesHeader}R3CN12345\tdevice\n',
          '-s R3CN12345 shell getprop': _sampleGetprop,
        }),
      );

      final devices = await client.getDevicesWithInfo();

      expect(devices, hasLength(1));
      final d = devices.first;
      expect(d.serial, 'R3CN12345');
      expect(d.status, DeviceStatus.online);
      expect(d.model, 'Pixel 8 Pro');
      expect(d.manufacturer, 'Google');
      expect(d.androidVersion, '14');
      expect(d.sdkVersion, 34);
      expect(d.isWifi, isFalse);
      expect(d.displayName, 'Pixel 8 Pro');
    });

    test('Wi-Fi serial sets isWifi true', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({
          'devices': '${_devicesHeader}192.168.1.5:5555\tdevice\n',
          '-s 192.168.1.5:5555 shell getprop': _sampleGetprop,
        }),
      );

      final devices = await client.getDevicesWithInfo();
      expect(devices.first.isWifi, isTrue);
    });

    test('offline device skips getprop, info fields are null', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({
          'devices': '${_devicesHeader}emulator-5554\toffline\n',
        }),
      );

      final devices = await client.getDevicesWithInfo();

      expect(devices, hasLength(1));
      final d = devices.first;
      expect(d.status, DeviceStatus.offline);
      expect(d.model, isNull);
      expect(d.manufacturer, isNull);
      expect(d.androidVersion, isNull);
      expect(d.sdkVersion, isNull);
    });

    test('unauthorized device skips getprop', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({
          'devices': '${_devicesHeader}192.168.1.8:5555\tunauthorized\n',
        }),
      );

      final devices = await client.getDevicesWithInfo();
      final d = devices.first;
      expect(d.status, DeviceStatus.unauthorized);
      expect(d.model, isNull);
    });

    test('getprop exception degrades gracefully', () async {
      final client = AdbClientImpl(
        runner: _MapRunner(
          {'devices': '${_devicesHeader}R3CN12345\tdevice\n'},
          throwOn: 'getprop',
        ),
      );

      final devices = await client.getDevicesWithInfo();

      expect(devices, hasLength(1));
      final d = devices.first;
      expect(d.status, DeviceStatus.online);
      expect(d.model, isNull);
      expect(d.displayName, 'R3CN12345'); // falls back to serial
    });

    test('mixes online and offline devices', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({
          'devices':
              '${_devicesHeader}R3CN12345\tdevice\nemulator-5554\toffline\n',
          '-s R3CN12345 shell getprop': _sampleGetprop,
        }),
      );

      final devices = await client.getDevicesWithInfo();

      expect(devices, hasLength(2));
      expect(
        devices.firstWhere((d) => d.serial == 'R3CN12345').model,
        'Pixel 8 Pro',
      );
      expect(
        devices.firstWhere((d) => d.serial == 'emulator-5554').model,
        isNull,
      );
    });

    test('empty device list returns empty', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({'devices': _devicesHeader}),
      );
      final devices = await client.getDevicesWithInfo();
      expect(devices, isEmpty);
    });
  });
}
