import 'package:flutter/material.dart';
import 'package:scrcpy_flutter/app_controller.dart';
import 'package:scrcpy_flutter/widgets/control_button.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class ControlButtonWidget extends StatelessWidget {
  const ControlButtonWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AppController();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
      ),
      width: 300,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: defaultNavButtons
            .map((b) => ControlButton(
                  icon: b.$1,
                  onPressed: () => controller.injectKey(b.$2),
                ))
            .toList(),
      ),
    );
  }
}
