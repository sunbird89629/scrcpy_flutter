import 'dart:async';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

/// Application-wide logger instance.
final appLogger = Logger('scrcpy_plus');

/// Manages device discovery, polling, and state.
class DeviceManager {
  DeviceManager({AdbClient? adb}) : adb = adb ?? const AdbClient();

  final AdbClient adb;
  final List<DeviceEntry> _devices = [];
  Timer? _pollTimer;
  final List<VoidCallback> _listeners = [];

  List<DeviceEntry> get devices => List.unmodifiable(_devices);
  bool get hasConnected => _devices.isNotEmpty;

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Set devices and notify listeners.
  void setDevices(List<DeviceEntry> devices) {
    _devices
      ..clear()
      ..addAll(devices);
    _notify();
  }

  /// Start periodic polling every [interval] seconds.
  void startPolling({Duration interval = const Duration(seconds: 30)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => refresh());
  }

  /// Stop polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Refresh device list from ADB.
  Future<void> refresh() async {
    try {
      final serials = await adb.getDevices();
      final entries = <DeviceEntry>[];
      for (final serial in serials) {
        try {
          final results = await Future.wait([
            adb.getDeviceInfo(serial),
            adb.listUserPackages(serial),
          ]);
          entries.add(
            DeviceEntry(
              info: results[0] as DeviceInfo,
              packages: results[1] as List<String>,
            ),
          );
        } catch (e) {
          appLogger.warning('Failed to get info for $serial: $e');
          entries.add(
            DeviceEntry(
              info: DeviceInfo(serial: serial, status: DeviceStatus.online),
            ),
          );
        }
      }
      setDevices(entries);
    } catch (e) {
      appLogger.severe('Device refresh failed: $e');
    }
  }

  void dispose() {
    stopPolling();
    _listeners.clear();
  }
}

typedef VoidCallback = void Function();
