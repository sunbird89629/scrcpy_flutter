import 'package:flutter/material.dart';
import 'package:scrcpy_app/app_controller.dart';
import 'package:scrcpy_app/device_list_widget.dart';

class DeviceControlView extends StatelessWidget {
  const DeviceControlView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController appController = AppController();
    return FutureBuilder(
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
  }
}
