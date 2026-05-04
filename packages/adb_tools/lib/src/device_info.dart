/// Connection and identification state of a single ADB device.
enum DeviceStatus { online, offline, unauthorized }

/// Rich device info gathered from `adb devices` + `adb shell getprop`.
class DeviceInfo {
  const DeviceInfo({
    required this.serial,
    required this.status,
    this.model,
    this.manufacturer,
    this.androidVersion,
    this.sdkVersion,
  });

  final String serial;
  final DeviceStatus status;
  final String? model; // ro.product.model
  final String? manufacturer; // ro.product.manufacturer
  final String? androidVersion; // ro.build.version.release
  final int? sdkVersion; // ro.build.version.sdk

  /// True when the serial contains ':' (wireless ADB address:port format).
  bool get isWifi => serial.contains(':');

  /// Human-readable title: model name if available, serial otherwise.
  String get displayName => model ?? serial;
}
