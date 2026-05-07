import 'package:flutter/material.dart';
import 'package:scrcpy_app/app_controller.dart';
import 'package:scrcpy_app/widgets/control_button.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class ControlButtonWidget extends StatelessWidget {
  static const _navButtons = [
    (Icons.arrow_back, ScrcpyKeycode.back),
    (Icons.circle_outlined, ScrcpyKeycode.home),
    (Icons.menu, ScrcpyKeycode.appSwitch),
  ];
  const ControlButtonWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AppController();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(100),
      ),
      width: 300,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _navButtons
            .map((b) => ControlButton(
                  icon: b.$1,
                  onPressed: () => controller.injectKey(b.$2),
                ))
            .toList(),
      ),
    );
  }
}
