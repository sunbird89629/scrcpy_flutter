import 'package:flutter/material.dart';
import 'package:scrcpy_flutter/app_controller.dart';
import 'package:scrcpy_flutter/views/device_control_view.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class PhoneView extends StatelessWidget {
  const PhoneView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppController(),
      builder: (context, _) {
        final appController = AppController();
        final mainContent = appController.running
            ? ScrcpyView(controller: appController.scrcpyViewController)
            : const DeviceControlView();
        final deviceInfo = appController.deviceInfo;
        final aspectRatio = deviceInfo != null && deviceInfo.screenWidth > 0
            ? deviceInfo.screenWidth / deviceInfo.screenHeight
            : 9 / 16;
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(aspectRatio: aspectRatio, child: mainContent),
        );
      },
    );
  }
}
