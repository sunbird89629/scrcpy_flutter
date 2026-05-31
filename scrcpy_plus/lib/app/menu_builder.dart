import 'package:tray_manager/tray_manager.dart';
import 'package:scrcpy_plus/device/device_entry.dart';

/// Builds the tray context menu from current app state.
class MenuBuilder {
  /// Key prefixes used for menu item identification.
  static const String launchPrefix = 'launch_';
  static const String disconnectPrefix = 'disconnect_';
  static const String infoPrefix = 'info_';

  /// Key for the "copy MCP address" menu item.
  static const String copyMcpKey = 'mcp_copy';

  static Menu buildMenu({
    required List<DeviceEntry> devices,
    String? mcpUrl,
    String? mcpError,
  }) {
    final items = <MenuItem>[];

    // MCP server status section (top).
    if (mcpUrl != null) {
      items.add(MenuItem(key: 'mcp_header', label: 'MCP server', disabled: true));
      items.add(MenuItem(key: copyMcpKey, label: '  $mcpUrl'));
      items.add(MenuItem.separator());
    } else if (mcpError != null) {
      items.add(MenuItem(
        key: 'mcp_error',
        label: 'MCP server: $mcpError',
        disabled: true,
      ));
      items.add(MenuItem.separator());
    }

    if (devices.isEmpty) {
      items.add(MenuItem(
        key: 'no_devices',
        label: 'No devices connected',
        disabled: true,
      ));
    } else {
      for (final device in devices) {
        items.add(MenuItem(
          key: '$launchPrefix${device.serial}',
          label: 'Launch scrcpy: ${device.menuLabel}',
        ));
        items.add(MenuItem(
          key: '$disconnectPrefix${device.serial}',
          label: '  Disconnect ${device.displayName}',
        ));
        if (device.detailLine != null) {
          items.add(MenuItem(
            key: '$infoPrefix${device.serial}',
            label: '  ${device.detailLine}',
            disabled: true,
          ));
        }
      }
    }

    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'pair', label: 'Pair new device...'));
    items.add(MenuItem(key: 'refresh', label: 'Refresh devices'));
    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'settings', label: 'Settings...'));
    items.add(MenuItem(key: 'quit', label: 'Quit'));

    return Menu(items: items);
  }
}
