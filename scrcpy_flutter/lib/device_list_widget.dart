import 'package:flutter/material.dart';

class DeviceListWidget extends StatelessWidget {
  const DeviceListWidget({
    super.key,
    required this.devices,
    required this.onItemTap,
  });

  final List<String> devices;
  final void Function(int index) onItemTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final deviceId = devices[index];
        return ListTile(
          title: Text(deviceId),
          onTap: () {
            onItemTap(index);
          },
        );
      },
    );
  }
}
