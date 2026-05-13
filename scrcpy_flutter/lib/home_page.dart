import 'dart:io';

import 'package:flutter/material.dart';
import 'package:scrcpy_flutter/views/control_view.dart';
import 'package:scrcpy_flutter/views/phone_view.dart';
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
    return Scaffold(
      body: Row(
        children: const [
          PhoneView(),
          ControlView(),
        ],
      ),
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
