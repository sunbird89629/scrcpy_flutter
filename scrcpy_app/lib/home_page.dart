import 'dart:io';

import 'package:flutter/material.dart';
import 'package:scrcpy_app/app_controller.dart';
import 'package:scrcpy_app/device_list_widget.dart';
import 'package:scrcpy_app/views/control_view.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TrayListener {
  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _initTray();
    _initWindow();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initTray() async {
    await trayManager.setIcon('assets/tray_icon.png');
    await trayManager.setToolTip('ScrcpyApp');
    await trayManager.setContextMenu(Menu(
      items: [
        MenuItem(key: 'show_window', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ],
    ));
  }

  Future<void> _initWindow() async {
    await windowManager.setPreventClose(true);
    windowManager.addListener(_WindowListener(_onWindowClose));
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
        break;
      case 'quit':
        trayManager.destroy();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _buildBody());
  }

  Widget _buildBody() {
    final appController = AppController();
    return ListenableBuilder(
      listenable: appController,
      builder: (context, child) {
        final mainContent = appController.running
            ? ScrcpyView(controller: appController.scrcpyViewController)
            : FutureBuilder(
                future: appController.scrcpyViewController.getDevices(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final devices = snapshot.data!;
                  if (devices.isEmpty) {
                    return const Center(child: Text('No device found'));
                  }
                  return DeviceListWidget(
                    devices: devices,
                    onItemTap: (index) {
                      appController.connectDevice(devices[index]);
                    },
                  );
                },
              );
        return Row(
          children: [
            Expanded(child: mainContent),
            ControlView(),
          ],
        );
      },
    );
  }
}

class _WindowListener extends WindowListener {
  _WindowListener(this.onClose);

  final VoidCallback onClose;

  @override
  void onWindowClose() {
    onClose();
  }
}

void _onWindowClose() {
  windowManager.hide();
}
