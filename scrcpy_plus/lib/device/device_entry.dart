import 'package:adb_tools/adb_tools.dart';

enum ConnectionType { usb, wifiAdb, wirelessDebug }

/// Extended device model with connection type and app list for menu display.
class DeviceEntry {
  DeviceEntry({required this.info, this.battery, this.packages = const []});

  final DeviceInfo info;
  final int? battery;
  final List<String> packages;

  String get serial => info.serial;
  String get displayName => info.displayName;
  bool get isWifi => info.isWifi;
  String get menuLabel => '$displayName ($connectionLabel)';

  ConnectionType get connectionType {
    if (info.serial.contains('._adb-tls-connect._tcp')) {
      return ConnectionType.wirelessDebug;
    }
    if (info.isWifi) return ConnectionType.wifiAdb;
    return ConnectionType.usb;
  }

  String get connectionLabel => switch (connectionType) {
    ConnectionType.usb => 'USB',
    ConnectionType.wifiAdb => 'WiFi',
    ConnectionType.wirelessDebug => 'Wireless',
  };

  /// Detail line: "Battery: 85% | Android 14 | 1080x2400"
  String? get detailLine {
    final parts = <String>[];
    if (battery != null) parts.add('Battery: $battery%');
    if (info.androidVersion != null) {
      parts.add('Android ${info.androidVersion}');
    }
    if (info.screenWidth > 0) {
      parts.add('${info.screenWidth.toInt()}x${info.screenHeight.toInt()}');
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }
}
