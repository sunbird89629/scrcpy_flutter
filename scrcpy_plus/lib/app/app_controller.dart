import 'dart:io';

import 'package:flutter/services.dart';
import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:scrcpy_plus/app/menu_builder.dart';
import 'package:scrcpy_plus/device/device_manager.dart';
import 'package:scrcpy_plus/device/pair_dialog.dart' show PairDialog;
import 'package:scrcpy_plus/device/pairing_service.dart';
import 'package:scrcpy_plus/mcp/mcp_server_controller.dart';
import 'package:scrcpy_plus/scrcpy/scrcpy_launcher.dart';
import 'package:scrcpy_plus/settings/settings_manager.dart';

/// Application-wide logger instance.
final appLogger = Logger('scrcpy_plus');

/// Central controller orchestrating tray, devices, scrcpy, and settings.
class AppController implements TrayListener {
  AppController({
    required this.settingsManager,
    AdbClient? adb,
  })  : adb = adb ?? const AdbClient(),
        pairingService = PairingService(adb: adb ?? const AdbClient()) {
    deviceManager = DeviceManager(adb: this.adb);
    launcher = ScrcpyLauncher();
    mcpController = McpServerController(adb: this.adb);
  }

  final SettingsManager settingsManager;
  final AdbClient adb;
  final PairingService pairingService;
  late final DeviceManager deviceManager;
  late final ScrcpyLauncher launcher;
  late final McpServerController mcpController;

  /// Static helpers for menu key parsing.
  static bool isLaunchAction(String key) =>
      key.startsWith(MenuBuilder.launchPrefix);
  static bool isDisconnectAction(String key) =>
      key.startsWith(MenuBuilder.disconnectPrefix);
  static String? serialFromAction(String key, String prefix) {
    if (!key.startsWith(prefix)) return null;
    return key.substring(prefix.length);
  }

  /// Initialize the app: load settings, start polling, set up tray.
  Future<void> init() async {
    final config = await settingsManager.loadConfig();
    launcher.config = config;

    deviceManager.addListener(_updateTrayMenu);
    await deviceManager.refresh();
    deviceManager.startPolling();

    await _initTray();

    await mcpController.start(config.mcpPort);
    await _updateTrayMenu();
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.png');
    await trayManager.setToolTip('scrcpy_plus');
    await _updateTrayMenu();
  }

  Future<void> _updateTrayMenu() async {
    final menu = MenuBuilder.buildMenu(
      devices: deviceManager.devices,
      mcpUrl: mcpController.serverUrl,
      mcpError: mcpController.errorMessage,
    );
    await trayManager.setContextMenu(menu);

    // Update icon based on connection state
    final icon = deviceManager.hasConnected
        ? 'assets/tray_icon_connected.png'
        : 'assets/tray_icon.png';
    await trayManager.setIcon(icon);
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == null) return;

    if (key == 'quit') {
      _quit();
    } else if (key == 'refresh') {
      deviceManager.refresh();
    } else if (key == 'pair') {
      _showPairDialog();
    } else if (key == 'settings') {
      _showSettingsDialog();
    } else if (key == MenuBuilder.copyMcpKey) {
      _copyMcpUrl();
    } else if (isLaunchAction(key)) {
      final serial = serialFromAction(key, MenuBuilder.launchPrefix);
      if (serial != null) _launchScrcpy(serial);
    } else if (isDisconnectAction(key)) {
      final serial = serialFromAction(key, MenuBuilder.disconnectPrefix);
      if (serial != null) _disconnectDevice(serial);
    }
  }

  Future<void> _launchScrcpy(String serial) async {
    try {
      await launcher.launch(serial);
    } catch (e) {
      appLogger.severe('Failed to launch scrcpy: $e');
    }
  }

  Future<void> _disconnectDevice(String serial) async {
    try {
      await pairingService.disconnect(serial);
      await deviceManager.refresh();
    } catch (e) {
      appLogger.severe('Failed to disconnect $serial: $e');
    }
  }

  Future<void> _showPairDialog() async {
    final address = await PairDialog.showAddressDialog();
    if (address == null) return;

    final error = PairingService.validateAddress(address);
    if (error != null) {
      appLogger.warning('Invalid address: $error');
      return;
    }

    final parts = address.split(':');
    final ip = parts[0];
    final port = int.parse(parts[1]);

    // Try direct connect first (for already-paired devices)
    try {
      await pairingService.connect(ip, port);
      await deviceManager.refresh();
      return;
    } catch (_) {
      // Need pairing code
    }

    final code = await PairDialog.showCodeDialog();
    if (code == null) return;

    final codeError = PairingService.validatePairingCode(code);
    if (codeError != null) {
      appLogger.warning('Invalid code: $codeError');
      return;
    }

    try {
      await pairingService.pair(ip, port, code);
      await pairingService.connect(ip, port);
      await deviceManager.refresh();
    } catch (e) {
      appLogger.severe('Pairing failed: $e');
    }
  }

  void _showSettingsDialog() {
    // TODO: Implement settings dialog
    appLogger.info('Settings dialog not yet implemented');
  }

  Future<void> _copyMcpUrl() async {
    final url = mcpController.serverUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    try {
      await Process.run('osascript', [
        '-e',
        'display notification "MCP address copied" with title "scrcpy_plus"',
      ]);
    } catch (e) {
      appLogger.warning('Failed to show copy notification: $e');
    }
  }

  void _quit() {
    launcher.dispose();
    deviceManager.dispose();
    // Fire-and-forget: the process exits immediately below, so the OS reclaims
    // the MCP server's port; we don't await a graceful socket shutdown.
    mcpController.stop();
    trayManager.destroy();
    exit(0);
  }

  void dispose() {
    launcher.dispose();
    deviceManager.dispose();
    mcpController.stop();
    trayManager.removeListener(this);
  }

  // TrayListener stubs
  @override
  void onTrayIconMouseUp() {}

  @override
  void onTrayIconRightMouseDown() {}

  @override
  void onTrayIconRightMouseUp() {}
}
