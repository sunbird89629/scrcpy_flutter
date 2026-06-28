import 'device_entry.dart';

/// One physical device with one or more active ADB connections (USB, WiFi,
/// wireless debugging). Connections are sorted USB-first for consistent display.
class DeviceGroup {
  DeviceGroup({
    required this.physicalSerial,
    required this.displayName,
    required List<DeviceEntry> connections,
  }) : connections = _sorted(connections);

  final String physicalSerial;
  final String displayName;
  final List<DeviceEntry> connections;

  bool get hasMultipleConnections => connections.length > 1;

  static List<DeviceEntry> _sorted(List<DeviceEntry> entries) {
    final order = {
      ConnectionType.usb: 0,
      ConnectionType.wifiAdb: 1,
      ConnectionType.wirelessDebug: 2,
    };
    return [...entries]..sort(
      (a, b) => order[a.connectionType]!.compareTo(order[b.connectionType]!),
    );
  }
}
