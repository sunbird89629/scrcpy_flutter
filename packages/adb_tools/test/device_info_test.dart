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

const _sampleGetprop = '''
[ro.product.model]: [Pixel 8 Pro]
[ro.product.manufacturer]: [Google]
[ro.build.version.release]: [14]
[ro.build.version.sdk]: [34]
[some.other.prop]: [value]
''';

void main() {
  group('AdbClient.getDeviceInfo', () {
    test('returns device with model info', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({
          '-s R3CN12345 shell getprop': _sampleGetprop,
        }),
      );

      final d = await client.getDeviceInfo('R3CN12345');

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
          '-s 192.168.1.5:5555 shell getprop': _sampleGetprop,
        }),
      );

      final d = await client.getDeviceInfo('192.168.1.5:5555');
      expect(d.isWifi, isTrue);
    });

    test('getprop exception throws AdbException', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({}, throwOn: 'getprop'),
      );

      expect(
        () => client.getDeviceInfo('R3CN12345'),
        throwsA(isA<AdbException>()),
      );
    });

    test('empty getprop returns null fields', () async {
      final client = AdbClientImpl(
        runner: _MapRunner({
          '-s R3CN12345 shell getprop': '',
        }),
      );

      final d = await client.getDeviceInfo('R3CN12345');

      expect(d.serial, 'R3CN12345');
      expect(d.status, DeviceStatus.online);
      expect(d.model, isNull);
      expect(d.manufacturer, isNull);
      expect(d.androidVersion, isNull);
      expect(d.sdkVersion, isNull);
      expect(d.displayName, 'R3CN12345'); // falls back to serial
    });
  });
}
