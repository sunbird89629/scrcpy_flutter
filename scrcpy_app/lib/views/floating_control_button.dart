import 'package:flutter/material.dart';
import 'package:scrcpy_app/app_controller.dart';
import 'package:scrcpy_app/widgets/control_button.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

class FloatingControlButton extends StatelessWidget {
  static const _navButtons = [
    (Icons.arrow_back, ScrcpyKeycode.back),
    (Icons.circle_outlined, ScrcpyKeycode.home),
    (Icons.menu, ScrcpyKeycode.appSwitch),
  ];
  const FloatingControlButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AppController();
    return SizedBox(
        height: 66,
        child: Material(
          // 关键 1：StadiumBorder 自动根据高度计算出完美的半圆弧度
          shape: const StadiumBorder(),

          // 关键 2：M3 规范通常使用 Surface 或 SecondaryContainer 颜色
          color: Theme.of(context).colorScheme.secondaryContainer,
          elevation: 4, // 增加一点悬浮感
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min, // 宽度自适应内容
              spacing: 24,
              children: _navButtons
                  .map((b) => ControlButton(
                        icon: b.$1,
                        onPressed: () => controller.injectKey(b.$2),
                      ))
                  .toList(),
            ),
          ),
        ));
  }
}
