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
    this.screenWidth = 0,
    this.screenHeight = 0,
  });

  final String serial;
  final DeviceStatus status;
  final String? model; // ro.product.model
  final String? manufacturer; // ro.product.manufacturer
  final String? androidVersion; // ro.build.version.release
  final int? sdkVersion; // ro.build.version.sdk
  final double screenWidth;
  final double screenHeight;

  /// True when the serial is an IP:port wireless ADB address.
  bool get isWifi => RegExp(r'^\d{1,3}(\.\d{1,3}){3}:\d+$').hasMatch(serial);

  /// Human-readable title: model name if available, serial otherwise.
  String get displayName => model ?? serial;

  /// Physical device serial used to group connections to the same hardware.
  ///
  /// Android 11+ wireless debugging produces an mDNS serial in the form
  /// `adb-<USB_SERIAL>-<RANDOM>._adb-tls-connect._tcp`. This getter extracts
  /// the underlying USB serial so USB and wireless entries can be grouped.
  /// For all other serial formats the serial itself is returned.
  String get physicalSerial {
    final m = RegExp(
      r'^adb-(\w+)-\w+\._adb-tls-connect\._tcp$',
    ).firstMatch(serial);
    return m?.group(1) ?? serial;
  }
}
