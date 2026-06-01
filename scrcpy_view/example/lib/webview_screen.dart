import 'package:flutter/material.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:scrcpy_view_example/app_controller.dart';
import 'package:scrcpy_view_example/views/control/control_view.dart';

class WebViewScreen extends StatelessWidget {
  const WebViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppController();
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Row(
        children: [
          Expanded(child: ScrcpyView(controller: controller.scrcpyController)),
          const ControlView(),
        ],
      ),
    );
  }
}
