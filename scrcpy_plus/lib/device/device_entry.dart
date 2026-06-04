import 'package:adb_tools/adb_tools.dart';

/// Extended device model with battery and display info for menu display.
class DeviceEntry {
  DeviceEntry({required this.info, this.battery});

  final DeviceInfo info;
  final int? battery; // percentage, null if unknown

  bool get isWifi => info.isWifi;
  String get displayName => info.displayName;
  String get serial => info.serial;

  String get connectionLabel => isWifi ? 'WiFi' : 'USB';

  /// Menu label: "Pixel 7 (WiFi)" or "ABCD1234 (USB)"
  String get menuLabel {
    final conn = connectionLabel;
    return '$displayName ($conn)';
  }

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
