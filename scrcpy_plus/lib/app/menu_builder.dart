import 'package:tray_manager/tray_manager.dart';

import '../device/device_group.dart';

/// Builds the tray context menu from current app state.
class MenuBuilder {
  static const String launchPrefix = 'launch_';
  static const String disconnectPrefix = 'disconnect_';
  static const String infoPrefix = 'info_';
  static const String flexLaunchPrefix = 'flex|';
  static const String copyMcpKey = 'mcp_copy';

  static Menu buildMenu({
    required List<DeviceGroup> groups,
    String? mcpUrl,
    String? mcpError,
  }) {
    final items = <MenuItem>[];

    if (mcpUrl != null) {
      items.add(
        MenuItem(key: 'mcp_header', label: 'MCP server', disabled: true),
      );
      items.add(MenuItem(key: copyMcpKey, label: '  $mcpUrl'));
      items.add(MenuItem.separator());
    } else if (mcpError != null) {
      items.add(
        MenuItem(
          key: 'mcp_error',
          label: 'MCP server: $mcpError',
          disabled: true,
        ),
      );
      items.add(MenuItem.separator());
    }

    if (groups.isEmpty) {
      items.add(
        MenuItem(
          key: 'no_devices',
          label: 'No devices connected',
          disabled: true,
        ),
      );
    } else {
      for (final group in groups) {
        items.addAll(_groupItems(group));
        items.add(MenuItem.separator());
      }
      // Remove the trailing separator before the action items.
      if (items.last.type == 'separator') items.removeLast();
    }

    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'pair', label: 'Pair new device...'));
    items.add(MenuItem(key: 'refresh', label: 'Refresh devices'));
    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'settings', label: 'Settings...'));
    items.add(MenuItem(key: 'quit', label: 'Quit'));

    return Menu(items: items);
  }

  static List<MenuItem> _groupItems(DeviceGroup group) {
    final multi = group.hasMultipleConnections;
    final items = <MenuItem>[];

    if (multi) {
      items.add(
        MenuItem(
          key: 'group_${group.physicalSerial}',
          label: group.displayName,
          disabled: true,
        ),
      );
    }

    for (final conn in group.connections) {
      final suffix = multi ? ' · ${conn.connectionLabel}' : '';
      final launchLabel = multi
          ? '  Launch scrcpy$suffix'
          : 'Launch scrcpy: ${conn.displayName} (${conn.connectionLabel})';

      items.add(
        MenuItem(key: '$launchPrefix${conn.serial}', label: launchLabel),
      );

      if (conn.packages.isNotEmpty) {
        final flexLabel = multi
            ? '  Launch App (flex display)$suffix…'
            : '  Launch App (flex display)…';
        items.add(
          MenuItem.submenu(
            label: flexLabel,
            submenu: Menu(
              items: [
                for (final pkg in conn.packages)
                  MenuItem(
                    key: '$flexLaunchPrefix${conn.serial}|$pkg',
                    label: pkg,
                  ),
              ],
            ),
          ),
        );
      }

      final disconnectLabel = multi
          ? '  Disconnect$suffix'
          : '  Disconnect ${conn.displayName}';
      items.add(
        MenuItem(
          key: '$disconnectPrefix${conn.serial}',
          label: disconnectLabel,
        ),
      );
    }

    final detail = group.connections.first.detailLine;
    if (detail != null) {
      items.add(
        MenuItem(
          key: '$infoPrefix${group.physicalSerial}',
          label: '  $detail',
          disabled: true,
        ),
      );
    }

    return items;
  }
}
